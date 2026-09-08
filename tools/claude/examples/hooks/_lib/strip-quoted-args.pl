#!/usr/bin/env perl
# Blanks the contents of shell quoted literals, so a detector looking for a COMMAND INVOCATION
# cannot fire on the same words appearing as data. Reads the command on stdin, writes the
# transformed command on stdout.
#
# A character walk rather than a regex: pairing quotes by regex mis-associates them on a busy
# command line, and cannot see that a $(...) or `...` inside double quotes is CODE rather than
# data — which silently hid real mutations such as OUT="$(terraform apply -auto-approve)".
#
# Two kinds of span survive blanking:
#   - command substitutions at any depth, because they are code, not text
#   - a quoted payload handed to a shell (bash -c "...", ssh host "...", eval "..."), because
#     there the string really is a command that will be re-parsed
#
# Deliberately NOT solved here: unquoted prose (`echo terraform apply`) still reads as an
# invocation. That direction is a false positive on a reminder-only hook, which is the safe way
# to be wrong; the alternative (requiring command position) trades it for silent misses.

use strict;
use warnings;

my $INVOKER = qr{
    (?: ^ | [;&|(] ) \s*
    (?: \S*/ )?
    (?: (?:ba|z|k|da|a)?sh\b [^"']{0,80} -c
      | eval\b
      | ssh\b [^"']{0,120}
    )
    \s* \z
}x;

my $s = do { local $/; <STDIN> };
$s = '' unless defined $s;

print walk($s);

sub walk {
    my ($s) = @_;
    my $n   = length $s;
    my $out = '';
    my $unq = '';    # unquoted text seen so far — the invoker test runs against this only
    my $i   = 0;

    while ($i < $n) {
        my $c = substr($s, $i, 1);

        if ($c eq '\\' && $i + 1 < $n) {
            $out .= substr($s, $i, 2);
            $unq .= substr($s, $i, 2);
            $i += 2;
            next;
        }

        if ($c eq '"' || $c eq "'") {
            my $keep = ($unq =~ $INVOKER) ? 1 : 0;
            my ($rendered, $next) = scan_quoted($s, $i, $c, $keep);
            $out .= $rendered;
            $i    = $next;
            $unq  = '';
            next;
        }

        $out .= $c;
        $unq .= $c;
        $i++;
    }
    return $out;
}

sub scan_quoted {
    my ($s, $start, $q, $keep) = @_;
    my $n        = length $s;
    my $i        = $start + 1;
    my $rendered = $q;
    my $data     = '';

    my $flush = sub {
        return unless length $data;
        $rendered .= $keep ? $data : 'QUOTED_ARG';
        $data = '';
    };

    while ($i < $n) {
        my $c = substr($s, $i, 1);

        if ($q eq '"' && $c eq '\\' && $i + 1 < $n) {
            $data .= substr($s, $i, 2);
            $i += 2;
            next;
        }

        if ($c eq $q) {
            $flush->();
            return ($rendered . $q, $i + 1);
        }

        # Single quotes are literal in shell, so only double quotes can contain code.
        # Recurse rather than preserve verbatim: a substitution is code, but code carries its own
        # quoted data, and keeping the whole span fired on args like $(run 'terraform apply').
        if ($q eq '"' && $c eq '$' && substr($s, $i + 1, 1) eq '(') {
            my $end   = match_paren($s, $i + 1);
            my $inner = substr($s, $i + 2, $end - $i - 2);
            $flush->();
            $rendered .= '$(' . walk($inner) . ')';
            $i = $end + 1;
            next;
        }

        if ($q eq '"' && $c eq '`') {
            my $end = index($s, '`', $i + 1);
            $end = $n - 1 if $end < 0;
            my $inner = substr($s, $i + 1, $end - $i - 1);
            $flush->();
            $rendered .= '`' . walk($inner) . '`';
            $i = $end + 1;
            next;
        }

        $data .= $c;
        $i++;
    }

    # Unterminated quote: the command could not run as written, so treat the tail as data.
    $flush->();
    return ($rendered, $n);
}

sub match_paren {
    my ($s, $open) = @_;
    my $n     = length $s;
    my $depth = 0;
    for (my $i = $open; $i < $n; $i++) {
        my $c = substr($s, $i, 1);
        $depth++ if $c eq '(';
        if ($c eq ')') {
            $depth--;
            return $i if $depth == 0;
        }
    }
    return $n - 1;
}
