#!/usr/bin/env perl
use strict;
use warnings;

my $values = @ARGV && $ARGV[0] eq '--values';
my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;
my ($output) = scan($input, 0, '', 0);
print $output;

sub executable_string {
    my @words = command_words($_[0]);
    return 0 unless @words;
    my $program = shift @words;
    return 1 if $program =~ m{(?:^|/)(?:eval|ssh)$};
    return 0 unless $program =~ m{(?:^|/)(?:bash|sh|zsh|ksh|dash|ash)$};
    return @words && $words[-1] =~ /^-[^-]*c/ ? 1 : 0;
}

sub command_words {
    my ($prefix) = @_;
    my (@words, $redirect);
    while ($prefix =~ /\G\s*(?:(\d*(?:>&|<&|>>|>|<)|&>)|((?:[^\s"'<>]+|'[^']*'|"[^"]*")+))/g) {
        if (defined $1) { $redirect = 1; next; }
        if ($redirect) { $redirect = 0; next; }
        push @words, $2;
    }
    while (@words) {
        if ($words[0] =~ /^[A-Za-z_]\w*=/) { shift @words; next; }
        if ($words[0] =~ /^(?:\{|if|then|else|elif|while|until|do)$/) { shift @words; next; }
        if ($words[0] eq '!') { shift @words; next; }
        if ($words[0] =~ /^(?:exec|time)$/) {
            my $wrapper = shift @words;
            while (@words && $words[0] =~ /^-/) {
                my $option = shift @words;
                shift @words if $wrapper eq 'exec' && $option eq '-a';
            }
            next;
        }
        if ($words[0] =~ m{(?:^|/)command$}) {
            shift @words;
            shift @words while @words && $words[0] =~ /^(?:-p|--)$/;
            next;
        }
        if ($words[0] =~ m{(?:^|/)env$}) {
            shift @words;
            while (@words && $words[0] =~ /^-/) {
                my $option = shift @words;
                shift @words if $option =~ /^(?:-u|-C|--unset|--chdir)$/;
            }
            next;
        }
        last;
    }
    return @words;
}

sub interpreter {
    my @words = command_words($_[0]);
    return 0 unless @words;
    my $program = shift @words;
    return 0 if $program eq 'eval';
    return 1 if $program =~ m{(?:^|/)ssh$};
    if ($program =~ m{(?:^|/)(python3?|perl|ruby|node)$}) {
        my $language = $1;
        while (@words) {
            my $word = shift @words;
            return 1 if $word eq '-';
            return !@words if $word eq '--';
            return 0 unless $word =~ /^-/;
            return 0 if $word =~ /^--(?:help|version)(?:=|$)/;
            return 0 if $language =~ /^python/ && $word =~ /^-(?:c|m|V)/;
            return 0 if $language eq 'perl' && $word =~ /^-[^-]*[eEvV]/;
            return 0 if $language eq 'ruby' && $word =~ /^-(?:e|v)/;
            return 0 if $language eq 'node' && $word =~ /^(?:-[epv]|--(?:eval|print)(?:=|$))/;
            shift @words if $word =~ /^(?:-[WXIMmr]|--require|--import)$/;
        }
        return 1;
    }
    return 0 unless $program =~ m{(?:^|/)(?:bash|sh|zsh|ksh|dash|ash)$};
    my $stdin = 0;
    while (@words) {
        my $word = shift @words;
        return $stdin unless $word =~ /^[-+]/;
        return 0 if $word =~ /^--(?:version|help)$/ || $word =~ /^-[^-]*c/;
        last if $word eq '--';
        $stdin = 1 if $word =~ /^-[^-]*s/;
        shift @words if $word =~ /^[-+][^-]*[oO]$/ || $word =~ /^--(?:rcfile|init-file)$/;
    }
    return $stdin || !@words;
}

sub finish_command {
    my ($prefix, $docs) = @_;
    if (@$docs) {
        my $executed = interpreter($prefix);
        $_->{executed} = $executed for @$docs;
        @$docs = ();
    }
}

sub backtick {
    my ($text, $start) = @_;
    my ($body, $i) = ('', $start + 1);
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        return ($body, $i + 1) if $char eq '`';
        if ($char eq '\\' && $i + 1 < length $text) {
            my $next = substr($text, $i + 1, 1);
            if ($next =~ /[\$`\\]/) {
                $body .= $next;
                $i += 2;
                next;
            }
            if ($next eq "\n") { $i += 2; next; }
        }
        $body .= $char;
        $i++;
    }
    die "Unterminated backtick substitution\n";
}

sub expansion {
    my ($text, $start) = @_;
    if (substr($text, $start, 1) eq '`') {
        my ($body, $next) = backtick($text, $start);
        my ($rendered) = scan($body, 0, '', 0);
        return ('$(' . $rendered . ')', $next);
    }
    my $arithmetic = substr($text, $start, 3) eq '$((';
    my ($body, $next) = scan($text, $start + ($arithmetic ? 3 : 2), $arithmetic ? '))' : ')', $arithmetic);
    return (($arithmetic ? '$((' : '$(') . $body . ($arithmetic ? '))' : ')'), $next);
}

sub quoted {
    my ($text, $start, $keep, $ansi) = @_;
    my $quote = substr($text, $start, 1);
    my ($data, $rendered, $expanded, $i) = ('', '', 0, $start + 1);
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        if ($char eq $quote) {
            if (!$expanded && $data =~ /\A[^\s"'\\`;|&<>()]*\z/) {
                return ($data, $i + 1);
            }
            $rendered .= ($values || $keep) ? $data : (length $data ? 'QUOTED_ARG' : '');
            return ($quote . $rendered . $quote, $i + 1);
        }
        if ($ansi && $char eq '\\') {
            my ($decoded, $next) = ansi_escape($text, $i);
            $data .= $decoded;
            $i = $next;
            next;
        }
        if ($quote eq '"' && $char eq '\\' && $i + 1 < length $text) {
            $data .= substr($text, $i, 2);
            $i += 2;
            next;
        }
        if ($quote eq '"' && ($char eq '`' || substr($text, $i, 2) eq '$(')) {
            $rendered .= ($values || $keep) ? $data : (length $data ? 'QUOTED_ARG' : '');
            $data = '';
            my ($code, $next) = expansion($text, $i);
            $rendered .= $code;
            $expanded = 1;
            $i = $next;
            next;
        }
        $data .= $char;
        $i++;
    }
    die "Unterminated quoted argument\n";
}

sub delimiter {
    my ($text, $start) = @_;
    my $i = $start + 2;
    my $tabs = substr($text, $i, 1) eq '-';
    $i++ if $tabs;
    $i++ while substr($text, $i, 1) =~ /[ \t]/;
    my ($word, $quoted, $seen) = ('', 0, 0);
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        last if $char =~ /[\s;&|<>()]/;
        die "Unsupported substitution-shaped heredoc delimiter\n" if $char eq '`' || substr($text, $i, 2) eq '$(';
        $seen = 1;
        my $ansi = 0;
        if ($char eq '$' && substr($text, $i + 1, 1) =~ /["']/) {
            $i++;
            $char = substr($text, $i, 1);
            $ansi = $char eq "'";
        }
        if ($char eq '"' || $char eq "'") {
            my $quote = $char;
            $quoted = 1;
            $i++;
            while ($i < length $text && substr($text, $i, 1) ne $quote) {
                $char = substr($text, $i, 1);
                if ($ansi && $char eq '\\') {
                    my ($decoded, $next) = ansi_escape($text, $i);
                    $word .= $decoded;
                    $i = $next;
                    next;
                }
                if ($quote eq '"' && $char eq '\\' && substr($text, $i + 1, 1) =~ /[\$`"\\\n]/) {
                    $i++;
                    $char = substr($text, $i, 1);
                    if ($char eq "\n") { $i++; next; }
                }
                $word .= $char;
                $i++;
            }
            die "Unterminated heredoc delimiter\n" if $i == length $text;
            $i++;
        } elsif ($char eq '\\') {
            $i++;
            die "Incomplete heredoc delimiter\n" if $i == length $text;
            $char = substr($text, $i++, 1);
            next if $char eq "\n";
            $quoted = 1;
            $word .= $char;
        } else {
            $word .= $char;
            $i++;
        }
    }
    die "Missing heredoc delimiter\n" unless $seen;
    return ({word => $word, quoted => $quoted, tabs => $tabs}, $i);
}

sub ansi_escape {
    my ($text, $start) = @_;
    my $tail = substr($text, $start + 1);
    my %escapes = (a => "\a", b => "\b", e => chr(27), E => chr(27), f => "\f",
                   n => "\n", r => "\r", t => "\t", v => chr(11), '\\' => '\\', "'" => "'", '"' => '"');
    my $char = substr($tail, 0, 1);
    return ($escapes{$char}, $start + 2) if exists $escapes{$char};
    if ($tail =~ /\A([0-7]{1,3})/) {
        my $byte = oct($1) & 255;
        die "NUL in heredoc delimiter\n" unless $byte;
        return (chr($byte), $start + 1 + length($1));
    }
    if ($tail =~ /\Ax([0-9a-fA-F]{1,2})/) {
        my $byte = hex($1);
        die "NUL in heredoc delimiter\n" unless $byte;
        return (chr($byte), $start + 2 + length($1));
    }
    die "Unsupported ANSI-C heredoc delimiter escape\n";
}

sub heredoc_body {
    my ($text, $start, $doc) = @_;
    my ($body, $i) = ('', $start);
    while ($i < length $text) {
        my $line = '';
        while ($i < length $text) {
            my $end = index($text, "\n", $i);
            $end = length $text if $end < 0;
            my $part = substr($text, $i, $end - $i);
            $i = $end + ($end < length $text ? 1 : 0);
            if (!$doc->{quoted} && $end < length $text && $part =~ /(\\+)$/ && length($1) % 2) {
                chop $part;
                $line .= $part;
                next;
            }
            $line .= $part;
            last;
        }
        $line =~ s/^\t+// if $doc->{tabs};
        return ($body, $i) if $line eq $doc->{word};
        $body .= $line . "\n";
    }
    return ($body, $i);
}

sub interpolations {
    my ($body) = @_;
    my ($out, $i) = ('', 0);
    while ($i < length $body) {
        my $char = substr($body, $i, 1);
        if ($char eq '\\' && substr($body, $i + 1, 1) =~ /[\$`\\\n]/) {
            $i += 2;
            next;
        }
        if ($char eq '`' || substr($body, $i, 2) eq '$(') {
            my ($code, $next) = expansion($body, $i);
            $out .= ' ' . $code;
            $i = $next;
            next;
        }
        $i++;
    }
    return $out;
}

sub scan {
    my ($text, $start, $stop, $arithmetic) = @_;
    my ($out, $simple, $i, $depth) = ('', '', $start, 0);
    my (@docs, @command_docs);
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        if ($stop && !$depth && substr($text, $i, length $stop) eq $stop) {
            die "Heredoc body missing before substitution end\n" if @docs;
            return ($out, $i + length $stop);
        }
        if ($char eq '\\' && $i + 1 < length $text) {
            my $next = substr($text, $i + 1, 1);
            my $escaped = $next eq "\n" ? '' : $next =~ /[A-Za-z0-9_.\/:@+=,~-]/ ? $next : substr($text, $i, 2);
            $out .= $escaped;
            $simple .= $escaped;
            $i += 2;
            next;
        }
        my $ansi = 0;
        if ($char eq '$' && substr($text, $i + 1, 1) =~ /["']/) {
            $i++;
            $char = substr($text, $i, 1);
            $ansi = $char eq "'";
        }
        if ($char eq '"' || $char eq "'") {
            my ($rendered, $next) = quoted($text, $i, executable_string($simple), $ansi);
            $out .= $rendered;
            $simple .= $rendered;
            $i = $next;
            next;
        }
        if ($char eq '`' || substr($text, $i, 2) eq '$(') {
            my ($code, $next) = expansion($text, $i);
            $out .= $code;
            $simple .= 'SUBSTITUTION';
            $i = $next;
            next;
        }
        if (!$arithmetic && substr($text, $i, 2) eq '((') {
            my ($body, $next) = scan($text, $i + 2, '))', 1);
            $out .= '((' . $body . '))';
            $simple .= 'ARITHMETIC';
            $i = $next;
            next;
        }
        if (!$arithmetic && $char eq '#' && ($i == $start || substr($text, $i - 1, 1) =~ /[\s;&|()]/)) {
            my $end = index($text, "\n", $i);
            $end = length $text if $end < 0;
            my $comment = substr($text, $i, $end - $i);
            $comment =~ tr/"'`\\()/      /;
            $out .= "; COMMENT $comment";
            $i = $end;
            next;
        }
        if (!$arithmetic && substr($text, $i, 2) eq '<<' && substr($text, $i + 2, 1) ne '<' && ($i == 0 || substr($text, $i - 1, 1) ne '<')) {
            my ($doc, $next) = delimiter($text, $i);
            push @docs, $doc;
            push @command_docs, $doc;
            $simple =~ s/(?:^|\s)\d+$//;
            $out .= ' HEREDOC ';
            $i = $next;
            next;
        }
        if ($char eq "\n" && @docs) {
            finish_command($simple, \@command_docs);
            $simple = '';
            $i++;
            $out .= "\n";
            for my $doc (@docs) {
                my ($body, $next) = heredoc_body($text, $i, $doc);
                $i = $next;
                if ($doc->{executed}) {
                    my ($code) = scan($body, 0, '', 0);
                    $out .= '$(' . $code . ")\n";
                } elsif (!$doc->{quoted}) {
                    $out .= interpolations($body) . "\n";
                }
            }
            @docs = ();
            next;
        }
        $depth++ if $char eq '(';
        $depth-- if $char eq ')' && $depth;
        if ($char =~ /[;|()\n]/ || ($char eq '&' && substr($text, $i - 1, 1) !~ /[<>]/ && substr($text, $i + 1, 1) ne '>')) {
            finish_command($simple, \@command_docs);
            $simple = '';
        } else {
            $simple .= $char eq "\t" ? ' ' : $char;
        }
        $out .= $char eq "\t" ? ' ' : $char;
        $i++;
    }
    die "Unterminated substitution\n" if $stop;
    return ($out, $i);
}
