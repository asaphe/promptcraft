#!/usr/bin/env perl
# Splits a command line into segments on UNQUOTED separators, NUL-delimited.
#
# Why a hook needs this: a flag test written against the whole command line answers for the
# wrong segment. `gh pr list --json url | jq -r '.[] | select(.state)'` carries a `select`
# that belongs to jq, not to gh, and a guard scanning the raw string cannot tell. Splitting
# first lets each detector run against the segment that actually owns the flag.

use strict;
use warnings;

my $s = do { local $/; <STDIN> };
$s = '' unless defined $s;

my $n   = length $s;
my $seg = '';
my $i   = 0;
my $dq  = 0;
my @out;

while ($i < $n) {
    my $c = substr($s, $i, 1);

    if ($c eq '\\' && $i + 1 < $n) {
        $seg .= substr($s, $i, 2);
        $i += 2;
        next;
    }

    # A single-quoted span interpolates nothing, so it is consumed whole. A double-quoted one
    # DOES interpolate, so it is only tracked: $( and a backtick inside it still open a nested
    # command, and consuming the span whole made `echo "$(rm -rf /)"` read as an allowlisted echo.
    if ($c eq "'" && !$dq) {
        my ($span, $next) = scan_quoted($s, $i, "'");
        $seg .= $span;
        $i = $next;
        next;
    }

    if ($c eq '"') {
        $dq = !$dq;
        $seg .= $c;
        $i++;
        next;
    }

    # `$(` and a backtick open a nested command; without splitting there, a `gh` invocation inside
    # one is buried mid-segment and never names itself at a segment start.
    if ($c eq '$' && $i + 1 < $n && substr($s, $i + 1, 1) eq '(') {
        # `$((` is arithmetic expansion, which bash resolves as arithmetic rather than as a nested
        # subshell, so it runs no command. Splitting there left a bare `(page+1))` segment that
        # named nothing and prompted. Kept whole instead; a `$(` or backtick written INSIDE the
        # arithmetic still splits on its own pass, so a command hidden there is judged as before.
        if ($i + 2 < $n && substr($s, $i + 2, 1) eq '(') {
            $seg .= '$((';
            $i += 3;
            next;
        }
        push @out, $seg;
        $seg = '';
        $i += 2;
        next;
    }

    if ($c eq '`') {
        push @out, $seg;
        $seg = '';
        $i++;
        next;
    }

    # `2>&1`, `>&2` and `&>file` are redirects, not separators. Splitting them yields a bare `1`
    # segment that matches no allowlist entry, so the caller prompts citing a reason of "1".
    if ($c eq '&' && !$dq) {
        my $prev = $i > 0        ? substr($s, $i - 1, 1) : '';
        my $next = $i + 1 < $n   ? substr($s, $i + 1, 1) : '';
        if ($prev eq '>' || $prev eq '<' || $next eq '>') {
            $seg .= $c;
            $i++;
            next;
        }
    }

    if (!$dq && ($c eq ';' || $c eq '|' || $c eq '&' || $c eq "\n")) {
        push @out, $seg;
        $seg = '';
        $i++;
        next;
    }

    $seg .= $c;
    $i++;
}

push @out, $seg;

# NUL-delimited: a segment may itself contain newlines (a quoted multi-line body), so a
# newline-delimited stream cannot be read back into whole segments.
for my $s (@out) {
    $s =~ s/^\s+|\s+$//g;
    print "$s\0" if length $s;
}

# An unterminated quote cannot run as written; consuming to end keeps its separators unsplit.
sub scan_quoted {
    my ($str, $start, $q) = @_;
    my $len = length $str;
    my $i   = $start + 1;

    while ($i < $len) {
        my $c = substr($str, $i, 1);
        if ($q eq '"' && $c eq '\\' && $i + 1 < $len) {
            $i += 2;
            next;
        }
        return (substr($str, $start, $i - $start + 1), $i + 1) if $c eq $q;
        $i++;
    }
    return (substr($str, $start), $len);
}
