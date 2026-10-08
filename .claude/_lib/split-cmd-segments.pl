#!/usr/bin/env perl
use strict;
use warnings;

my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;
my $scoped = @ARGV && $ARGV[0] eq '--scoped';
my @records;
collect_segments($input, \@records, $scoped);

for my $record (@records) {
    my ($type, $segment) = @$record;
    if ($scoped) {
        print "$type\0";
        print "$segment\0" if $type eq 'S';
    } elsif ($type eq 'S') {
        print "$segment\0";
    }
}
print "Z\0" if $scoped;

sub emit_segment {
    my ($out, $segment) = @_;
    $segment =~ s/^\s+|\s+$//g;
    push @$out, ['S', $segment] if length $segment;
}

sub emit_scope { push @{$_[0]}, [$_[1]]; }

# see: README.md § split-cmd-segments.pl — the enclosing segment stays open, so `git -C "$(…)" push` reaches the push check whole
sub substitution {
    my ($text, $start, $end, $out, $scoped, $quote, $before) = @_;
    my $inner = substr($text, $start, $end - $start);
    emit_scope($out, 'E') if $scoped;
    collect_segments($inner, $out, $scoped);
    emit_scope($out, 'X') if $scoped;
    # see: README.md § split-cmd-segments.pl — TOPLEVEL, and why a value after `=` or `:` keeps its word
    my $word = $inner =~ /\A\s*git\s+rev-parse\s+--show-toplevel\s*\z/ ? 'TOPLEVEL' : 'SUBSTITUTION';
    return $word if $scoped && $quote eq '"';
    return $before =~ /[=:]\z/ ? "$word " : " $word ";
}

sub collect_segments {
    my ($text, $out, $scoped) = @_;
    my ($segment, $quote, $i) = ('', '', 0);
    my $length = length $text;

    while ($i < $length) {
        my $char = substr($text, $i, 1);

        if ($quote ne "'" && $char eq '\\' && $i + 1 < $length) {
            $segment .= substr($text, $i, 2);
            $i += 2;
            next;
        }
        if ($quote eq "'") {
            $quote = '' if $char eq "'";
            $segment .= $char;
            $i++;
            next;
        }
        if ($quote ne '"' && $char eq "'") {
            $quote = "'";
            $segment .= $char;
            $i++;
            next;
        }
        if ($char eq '"') {
            $quote = $quote eq '"' ? '' : '"';
            $segment .= $char;
            $i++;
            next;
        }
        if ($char eq '$' && $i + 1 < $length && substr($text, $i + 1, 1) eq '(') {
            if ($i + 2 < $length && substr($text, $i + 2, 1) eq '(') {
                $segment .= '$((';
                $i += 3;
                next;
            }
            my $end = command_substitution_end($text, $i + 1);
            if (defined $end) {
                $segment .= substitution($text, $i + 2, $end, $out, $scoped, $quote, $segment);
                $i = $end + 1;
                next;
            }
        }
        # Process substitution runs its command too; `cat <(…)` was hard only because a trailing `)` was trimmed.
        if (!$quote && ($char eq '<' || $char eq '>') && $i + 1 < $length && substr($text, $i + 1, 1) eq '(') {
            my $end = command_substitution_end($text, $i + 1);
            if (defined $end) {
                $segment .= substitution($text, $i + 2, $end, $out, $scoped, $quote, $segment);
                $i = $end + 1;
                next;
            }
        }
        if ($char eq '`') {
            my $end = backtick_end($text, $i);
            if (defined $end) {
                $segment .= substitution($text, $i + 1, $end, $out, $scoped, $quote, $segment);
                $i = $end + 1;
                next;
            }
        }
        if (!$quote && $char eq '&') {
            my $previous = $i > 0 ? substr($text, $i - 1, 1) : '';
            my $next = $i + 1 < $length ? substr($text, $i + 1, 1) : '';
            if ($previous eq '>' || $previous eq '<' || $next eq '>') {
                $segment .= $char;
                $i++;
                next;
            }
        }
        if (!$quote && ($char eq ';' || $char eq '|' || $char eq '&' || $char eq "\n")) {
            emit_segment($out, $segment);
            $segment = '';
            $i++;
            next;
        }
        $segment .= $char;
        $i++;
    }
    emit_segment($out, $segment);
}

sub command_substitution_end {
    my ($text, $open) = @_;
    my ($depth, $quote, $i) = (1, '', $open + 1);
    my $length = length $text;

    while ($i < $length) {
        my $char = substr($text, $i, 1);
        if ($quote ne "'" && $char eq '\\' && $i + 1 < $length) {
            $i += 2;
            next;
        }
        if ($quote eq "'") {
            $quote = '' if $char eq "'";
            $i++;
            next;
        }
        if ($quote ne '"' && $char eq "'") {
            $quote = "'";
            $i++;
            next;
        }
        if ($char eq '"') {
            $quote = $quote eq '"' ? '' : '"';
            $i++;
            next;
        }
        if ($char eq '`') {
            my $end = backtick_end($text, $i);
            return unless defined $end;
            $i = $end + 1;
            next;
        }
        if ($char eq '$' && $i + 1 < $length && substr($text, $i + 1, 1) eq '(') {
            my $end = command_substitution_end($text, $i + 1);
            return unless defined $end;
            $i = $end + 1;
            next;
        }
        if (!$quote && $char eq '(') {
            $depth++;
            $i++;
            next;
        }
        if (!$quote && $char eq ')') {
            $depth--;
            return $i if $depth == 0;
        }
        $i++;
    }
    return;
}

sub backtick_end {
    my ($text, $open) = @_;
    my $length = length $text;
    for (my $i = $open + 1; $i < $length; $i++) {
        if (substr($text, $i, 1) eq '\\' && $i + 1 < $length) {
            $i++;
            next;
        }
        return $i if substr($text, $i, 1) eq '`';
    }
    return;
}
