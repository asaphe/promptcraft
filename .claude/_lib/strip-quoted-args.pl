#!/usr/bin/env perl
use strict;
use warnings;

my $values = @ARGV && $ARGV[0] eq '--values';
# see: README.md § strip-quoted-args.pl, "--bodies" — the raw command with only its data heredoc bodies stripped
my $bodies = @ARGV && $ARGV[0] eq '--bodies';
my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;

my $SHELL = qr{(?:^|/)(?:bash|sh|zsh|ksh|mksh|pdksh|oksh|loksh|lksh|dash|ash|posh|yash|csh|tcsh|fish)$};
my $LANG = qr{(?:^|/)(python3?|perl|ruby|node)$};
my $STDIN_WRAPPER = qr{(?:^|/)(?:timeout|gtimeout|nice|nohup|sudo|doas|stdbuf|setsid|ionice|caffeinate|arch|runuser|chroot|unbuffer|chrt|taskset|busybox)$};
# Anything in a non-shell body that can start a process; such a body that is unreadable as shell fails closed.
my $CAPABLE = qr{\bqx\s*[^\w\s]|%x\s*[^\w\s]|\b(?:subprocess|Open3|child_process|pty)\s*[.(]|\b(?:import|from|require)\s*\(?\s*['"]?(?:subprocess|pty|child_process|open3)\b|\b(?:system|exec\w*|spawn\w*|popen|Popen|check_output|check_call|getoutput|getstatusoutput)\s*[(\["']};
# A heredoc's id is its context plus its offset, so a body rendered as code on a later pass shifts no other id.
our $CTX = 'top';
our (%FORCE, %LATE, @TOPDOCS, @EXTRA);
# A backtick body with no escapes is a verbatim slice of the input, so its heredocs keep input offsets.
our ($BASE, $VERBATIM) = (0, 1);

# see: README.md § strip-quoted-args.pl — a heredoc found to be code after its body was rendered re-runs the scan
my $output;
for (1 .. 64) {
    %LATE = ();
    @TOPDOCS = ();
    @EXTRA = ();
    ($output) = scan($input, 0, '', 0);
    last unless %LATE;
    $FORCE{$_} = $LATE{$_} for keys %LATE;
}
die "Heredoc classification did not settle\n" if %LATE;
$output = raw_bodies() if $bodies;
print $output;

sub raw_bodies {
    my @edits;
    # An unquoted body's `$( … )` and backticks run even when the body is data, so that body stays.
    my $live = sub { !$_[0]{quoted} && substr($input, $_[0]{span}[0], $_[0]{span}[1] - $_[0]{span}[0]) =~ /\$\(|`/ };
    for my $doc (grep { !$_->{executed} && $_->{span} && !$live->($_) } @TOPDOCS) {
        push @edits, [@{$doc->{span}}, ''], [@{$doc->{open}}, '<<STRIPPED_HEREDOC>>'];
    }
    my $raw = $input;
    for my $edit (sort { $b->[0] <=> $a->[0] } @edits) {
        substr($raw, $edit->[0], $edit->[1] - $edit->[0]) = $edit->[2];
    }
    return @EXTRA ? join("\n", $raw, @EXTRA) : $raw;
}

sub mark {
    my ($kind, @docs) = @_;
    return unless $kind;
    for my $doc (@docs) {
        next if ($doc->{executed} || 0) >= $kind;
        $doc->{executed} = $kind;
        $LATE{$doc->{id}} = $kind if $doc->{rendered};
    }
}

sub executable_string {
    my @words = command_words($_[0]);
    return 0 unless @words;
    my $program = shift @words;
    # see: README.md § strip-quoted-args.pl — a wrapper execs its operands, so a shell or ssh after it still runs the string
    if ($program =~ m{(?:^|/)(?:xargs|find|script)$} || $program =~ $STDIN_WRAPPER) {
        shift @words while @words && $words[0] !~ m{(?:^|/)ssh$} && $words[0] !~ $SHELL;
        return 0 unless @words;
        $program = shift @words;
    }
    return 1 if $program =~ m{(?:^|/)(?:eval|ssh|watch|parallel)$};
    return 1 if $program =~ m{(?:^|/)(?:su|flock)$} && @words && $words[-1] =~ /^(?:-[^-]*c|--command=?)$/;
    return 0 unless $program =~ $SHELL;
    # `-c -- '<code>'` ends the options before the string, which is still the code.
    pop @words if @words > 1 && $words[-1] eq '--';
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
        if ($words[0] =~ /^(?:\{|\}|if|then|else|elif|while|until|do)$/) { shift @words; next; }
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

# The program a command runs after its wrappers: `sudo -u x sh` runs sh, with the wrapper's stdin.
sub program_words {
    my @words = command_words($_[0]);
    return () unless @words;
    if ($words[0] =~ $STDIN_WRAPPER) {
        shift @words while @words && $words[0] !~ $SHELL && $words[0] !~ $LANG && $words[0] !~ m{(?:^|/)ssh$};
    }
    return @words;
}

# 2 = this command runs its stdin as shell code, 1 = as another language's code, 0 = reads it as data.
sub interpreter {
    my @words = program_words($_[0]);
    return 0 unless @words;
    my $program = shift @words;
    return 0 if $program eq 'eval';
    return 2 if $program =~ m{(?:^|/)ssh$};
    if ($program =~ $LANG) {
        my $language = $1;
        while (@words) {
            my $word = shift @words;
            return 1 if $word eq '-';
            return @words ? 0 : 1 if $word eq '--';
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
    return 0 unless $program =~ $SHELL;
    my $stdin = 0;
    while (@words) {
        my $word = shift @words;
        return $stdin ? 2 : 0 unless $word =~ /^[-+]/;
        return 0 if $word =~ /^--(?:version|help)$/ || $word =~ /^-[^-]*c/;
        last if $word eq '--';
        $stdin = 1 if $word =~ /^-[^-]*s/;
        shift @words if $word =~ /^[-+][^-]*[oO]$/ || $word =~ /^--(?:rcfile|init-file)$/;
    }
    return $stdin || !@words ? 2 : 0;
}

# What a process substitution's output becomes when the command reads it as a file: `source <(…)`, `bash <(…)`.
sub file_reader {
    my @words = program_words($_[0]);
    return 0 unless @words;
    # `bash -c '…' <( … )` runs its -c string; the substitution's path is only `$0`.
    return 0 if $words[0] =~ $SHELL && grep { /^-[^-]*c/ } @words[1 .. $#words];
    return 2 if $words[0] =~ m{^(?:source|\.)$} || $words[0] =~ $SHELL;
    return 1 if $words[0] =~ $LANG;
    return 0;
}

# `$( … )` at command position runs its output, and so does one a wrapper runs (`sudo $( … )`); `X=$( … )` assigns it.
sub at_command_position {
    my ($simple) = @_;
    return 0 unless $simple !~ /\S/ || $simple =~ /\s\z/;
    my @words = command_words($simple);
    return 1 unless @words;
    return $words[0] =~ $STDIN_WRAPPER || $words[0] =~ m{(?:^|/)xargs$} ? 1 : 0;
}

# A Python, Perl, Ruby or Node inline-code flag right before the string: `python3 -c '…'`, `perl -e '…'`.
sub lang_inline {
    my @words = program_words($_[0]);
    return 0 unless @words >= 2 && $words[0] =~ $LANG;
    my ($language, $flag) = ($1, $words[-1]);
    return $flag =~ /^-[^-]*c$/ if $language =~ /^python/;
    return $flag =~ /^-[^-]*[eE]$/ if $language eq 'perl';
    return $flag =~ /^-[^-]*e$/ if $language eq 'ruby';
    return $flag =~ /^(?:-[^-]*[ep]|--eval|--print)$/;
}

# One here-string word, unquoted piece by piece: `'git push'" main"`, `git\ push`, `$'…'`. A substitution in it runs wherever it is, so it stays visible.
sub here_word {
    my ($text, $i) = @_;
    my ($value, $visible, @docs) = ('', '');
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        last if $char =~ /[\s;&|<>()]/;
        if ($char eq '\\') {
            $value .= substr($text, $i + 1, 1);
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
            my ($rendered, $next, $inner) = quoted($text, $i, 1, $ansi);
            push @docs, @$inner;
            $visible .= ' ' . (quoted($text, $i, 0, $ansi))[0] if @$inner || $rendered =~ /\$\(/;
            $rendered = $2 if $rendered =~ /\A(["'])(.*)\1\z/s;
            $value .= $rendered;
            $i = $next;
            next;
        }
        if ($char eq '`' || substr($text, $i, 2) eq '$(') {
            my ($code, $next, $inner) = expansion($text, $i);
            push @docs, @$inner;
            $value .= $code;
            $visible .= ' ' . $code;
            $i = $next;
            next;
        }
        $value .= $char;
        $i++;
    }
    return ($value, $i, \@docs, $visible);
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
        local $CTX = "$CTX/bt$start";
        local $BASE = $BASE + $start + 1;
        local $VERBATIM = $VERBATIM && $body eq substr($text, $start + 1, $next - $start - 2);
        my ($rendered, undef, $docs) = scan($body, 0, '', 0);
        return ('$(' . $rendered . ')', $next, $docs);
    }
    my $arithmetic = substr($text, $start, 3) eq '$((';
    my ($body, $next, $docs) = scan($text, $start + ($arithmetic ? 3 : 2), $arithmetic ? '))' : ')', $arithmetic);
    return (($arithmetic ? '$((' : '$(') . $body . ($arithmetic ? '))' : ')'), $next, $docs);
}

# A chunk with no space or shell syntax cannot form a command phrase, so a path beside a substitution stays readable.
sub masked {
    my ($data, $keep) = @_;
    return $data if $values || $keep || $data =~ /\A[^\s"'\\`;|&<>()\$]*\z/;
    return length $data ? 'QUOTED_ARG' : '';
}

sub quoted {
    my ($text, $start, $keep, $ansi) = @_;
    my $quote = substr($text, $start, 1);
    my ($data, $rendered, $expanded, $i) = ('', '', 0, $start + 1);
    my @docs;
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        if ($char eq $quote) {
            if (!$expanded && $data =~ /\A[^\s"'\\`;|&<>()]*\z/) {
                return ($data, $i + 1, \@docs);
            }
            $rendered .= masked($data, $keep);
            return ($quote . $rendered . $quote, $i + 1, \@docs);
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
            $rendered .= masked($data, $keep);
            $data = '';
            my ($code, $next, $inner) = expansion($text, $i);
            push @docs, @$inner;
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

sub string_literal {
    my ($body, $pos) = @_;
    pos($body) = $pos;
    return () unless $body =~ /\G[rRbBuUfF]{0,2}('''|"""|'|"|`)/gc;
    my ($quote, $value) = ($1, '');
    while (pos($body) < length $body) {
        return ($value, pos($body)) if $body =~ /\G\Q$quote\E/gc;
        # The language decodes these before the call runs: `"git\x20push"` runs `git push`.
        if ($body =~ /\G\\(?:x([0-9a-fA-F]{2})|u([0-9a-fA-F]{4})|U([0-9a-fA-F]{8})|([0-7]{1,3}))/gc) {
            $value .= chr(hex($1 // $2 // $3 // '') || oct($4 // 0));
            next;
        }
        if ($body =~ /\G\\([nrt])/gc) { $value .= {n => "\n", r => "\r", t => "\t"}->{$1}; next; }
        if ($body =~ /\G\\(.)/gcs) { $value .= $1; next; }
        return () if length $quote == 1 && $quote ne '`' && $body =~ /\G\n/gc;
        $body =~ /\G(.)/gcs;
        $value .= $1;
    }
    return ();
}

# The strings a body hands to a shell-running call, joined: `os.system('…')`, `subprocess.run(["git", "push", …])`.
sub exec_calls {
    my ($doc, $body) = @_;
    my $out = '';
    # A whole-line `#` or `//` comment runs nothing in any of these languages.
    $body =~ s{^[ \t]*(?:#|//).*$}{}mg;
    my $calls = qr{(?:os\.(?:system|popen|exec\w*|spawn\w*)|subprocess\.\w+|\b(?:Popen|check_output|check_call|system|execSync|execFileSync|execFile|exec|spawnSync|spawn))\b};
    while ($body =~ /$calls\s*\(?\s*(?:\w+\s*=\s*)?\[?\s*/g) {
        my ($pos, @parts) = (pos($body));
        while (my ($value, $next) = string_literal($body, $pos)) {
            push @parts, $value;
            pos($body) = $next;
            $body =~ /\G\s*,?\s*/gc;
            $pos = pos($body);
        }
        pos($body) = $pos;
        next unless @parts;
        push @EXTRA, join(' ', @parts) if $bodies;
        local $CTX = "$doc->{id}/call$pos";
        my $code = eval { (scan(join(' ', @parts), 0, '', 0))[0] };
        $out .= "\$($code)\n" if defined $code;
    }
    # Any delimiter, and a bracket pair nests: `qx/…/`, `qx{…}`, `qx(echo (a) b)`.
    while ($body =~ /(?:\bqx|%x)\s*([^\w\s])/g) {
        my $open = $1;
        my $close = {qw/( ) { } [ ] < >/}->{$open} // $open;
        my ($start, $j, $depth) = (pos($body), pos($body), 1);
        while ($j < length $body) {
            my $char = substr($body, $j, 1);
            if ($char eq '\\') { $j += 2; next; }
            if ($char eq $close) { last unless --$depth; }
            elsif ($char eq $open) { $depth++; }
            $j++;
        }
        last if $j >= length $body;
        my $command = substr($body, $start, $j - $start);
        pos($body) = $j + 1;
        push @EXTRA, $command if $bodies;
        local $CTX = "$doc->{id}/qx$start";
        my $code = eval { (scan($command, 0, '', 0))[0] };
        $out .= "\$($code)\n" if defined $code;
    }
    return $out;
}

# see: README.md § strip-quoted-args.pl — a Python, Perl, Ruby or Node body is not shell, so a failed shell parse proves nothing
sub render_body {
    my ($doc, $body) = @_;
    local $CTX = $doc->{id};
    local $VERBATIM = 0;
    push @EXTRA, $body if $bodies && defined $doc->{inline} && ($doc->{executed} || 0) == 2;
    if (($doc->{executed} || 0) == 2) {
        my ($code) = scan($body, 0, '', 0);
        return '$(' . $code . ")\n";
    }
    if ($doc->{executed}) {
        # A whole-line `#` or `//` comment runs nothing in Python, Perl, Ruby or Node, so it is not read as shell either.
        $body =~ s{^[ \t]*(?:#|//).*$}{}mg;
        if ($bodies) { push @EXTRA, $1 while $body =~ /`([^`]*)`/g; }
        my $calls = exec_calls($doc, $body);
        my $code = eval { (scan($body, 0, '', 0))[0] };
        return '$(' . $code . ")\n" . $calls if defined $code;
        die "Unreadable non-shell body that can run commands\n" if $body =~ $CAPABLE;
        my $out = ($doc->{quoted} ? '' : interpolations($body)) . $calls;
        # Perl and Ruby run a backtick span; in Node it is a template literal, so one that is not shell is skipped.
        while ($body =~ /`([^`]*)`/g) {
            my $span = $1;
            local $CTX = "$doc->{id}/bt" . pos($body);
            my $inner = eval { (scan($span, 0, '', 0))[0] };
            $out .= "\n\$($inner)" if defined $inner;
        }
        return $out . "\n";
    }
    return $doc->{quoted} ? '' : interpolations($body) . "\n";
}

sub scan {
    my ($text, $start, $stop, $arithmetic) = @_;
    my ($out, $simple, $i, $depth) = ('', '', $start, 0);
    # The chunks of one word share its verdict: `'a '\''b'\'' c'` is one shell string, not a string and then data.
    my $word_keep = 0;
    # A substitution in an argument feeds the command's output, never its stdin: `sh -s -- "$( … )"` is data.
    my (@docs, @command_docs, @arg_docs, @piped_docs, @frames, @all);
    my $pipe_pending = 0;
    # A group or `>( … )` that ran an interpreter, just closed: a heredoc on the same command feeds it (`(bash) <<EOF`).
    my $attached = 0;
    my $open_braces = sub {
        my ($prefix) = @_;
        while ($prefix =~ s/\A(\s*(?:!\s+|time\s+|if\s+|then\s+|else\s+|elif\s+|while\s+|until\s+|do\s+)*)\{(?=\s|\z)/$1/) {
            push @frames, {kind => 'brace', stdin => [@piped_docs], out => []};
        }
        return $prefix;
    };
    # see: README.md § strip-quoted-args.pl — a group's stdin reaches every command in it, and its output is every command's
    my $finish = sub {
        my ($prefix, $pipe) = @_;
        $prefix = $open_braces->($prefix);
        while ($prefix =~ s/\A(\s*)\}(?=\s|\z)/$1/) {
            last unless @frames && $frames[-1]{kind} eq 'brace';
            my $brace = pop @frames;
            push @arg_docs, @{$brace->{out}};
            $attached = $brace->{seen} if ($brace->{seen} || 0) > $attached;
        }
        my $kind = interpreter($prefix);
        mark($kind, @command_docs, @piped_docs, map { @{$_->{stdin}} } @frames) if $kind;
        mark($attached, @command_docs) if $attached;
        $attached = 0;
        for my $frame (@frames) { $frame->{seen} = $kind if $kind > ($frame->{seen} || 0); }
        push @{$frames[-1]{out}}, @command_docs, @arg_docs, @piped_docs if @frames;
        @piped_docs = $pipe ? (@piped_docs, @command_docs, @arg_docs) : ();
        $pipe_pending = $pipe ? 1 : 0;
        @command_docs = ();
        @arg_docs = ();
    };
    my $flush_inline = sub {
        my $rendered = join '', map { $_->{rendered} = 1; render_body($_, $_->{inline}) } grep { defined $_->{inline} } @docs;
        @docs = ();
        return length $rendered ? "\n" . $rendered : '';
    };
    my $substituted = sub {
        my ($docs, $code) = @_;
        return unless @$docs;
        push @all, @$docs;
        if ($code) { mark(2, @$docs); } else { push @arg_docs, @$docs; }
    };
    while ($i < length $text) {
        my $char = substr($text, $i, 1);
        if ($stop && !$depth && substr($text, $i, length $stop) eq $stop) {
            die "Heredoc body missing before substitution end\n" if grep { !defined $_->{inline} } @docs;
            $finish->($simple, 0);
            $out .= $flush_inline->();
            return ($out, $i + length $stop, \@all);
        }
        # A here-string is its command's stdin, as a heredoc body is, so the same rules decide whether it is code.
        if (!$arithmetic && $simple =~ /<<<\s*\z/ && $char !~ /\s/) {
            my ($value, $next, $inner, $visible) = here_word($text, $i);
            my $id = "$CTX:hs$i";
            my $doc = {id => $id, inline => $value, quoted => 1, executed => $FORCE{$id} || 0};
            push @docs, $doc;
            push @command_docs, $doc, @$inner;
            push @all, $doc, @$inner;
            $out .= ' HERESTRING' . $visible . ' ';
            $simple .= 'HERESTRING';
            $i = $next;
            next;
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
            my $keep = $word_keep || executable_string($simple);
            # `python3 -c '…'` is that language's code: read like a heredoc body it runs.
            if (!$keep && !$arithmetic && lang_inline($simple)) {
                # The whole word, chunk by chunk, as the shell joins it: `'os.system('"'git push…'"')'`.
                my ($code) = here_word($text, $ansi ? $i - 1 : $i);
                my $id = "$CTX:lc$i";
                push @docs, {id => $id, inline => $code, quoted => 1, executed => ($FORCE{$id} || 0) > 1 ? $FORCE{$id} : 1};
            }
            $word_keep = $keep;
            my ($rendered, $next, $inner) = quoted($text, $i, $keep, $ansi);
            $substituted->($inner, $keep || at_command_position($simple));
            $out .= $rendered;
            $simple .= $rendered;
            $i = $next;
            next;
        }
        if ($char eq '`' || substr($text, $i, 2) eq '$(') {
            my ($code, $next, $inner) = expansion($text, $i);
            $substituted->($inner, executable_string($simple) || at_command_position($simple));
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
            $doc->{id} = "$CTX:$i";
            $doc->{executed} = $FORCE{$doc->{id}} || 0;
            $doc->{open} = [$BASE + $i, $BASE + $next];
            push @TOPDOCS, $doc if $VERBATIM;
            push @docs, $doc;
            push @command_docs, $doc;
            push @all, $doc;
            $simple =~ s/(?:^|\s)\d+$//;
            $out .= ' HEREDOC ';
            $i = $next;
            next;
        }
        # A pipeline continues past a newline after `|`, and past the heredoc bodies that newline starts.
        my $continues = $pipe_pending && $simple !~ /\S/;
        if ($char eq "\n" && @docs) {
            $finish->($simple, 0) unless $continues;
            $simple = '';
            $i++;
            $out .= "\n";
            for my $doc (@docs) {
                my $body = $doc->{inline};
                unless (defined $body) {
                    my $from = $i;
                    ($body, $i) = heredoc_body($text, $i, $doc);
                    $doc->{span} = [$BASE + $from, $BASE + $i];
                }
                $out .= render_body($doc, $body);
                $doc->{rendered} = 1;
            }
            @docs = ();
            next;
        }
        if ($char eq '(') {
            $depth++;
            my $before = $i > 0 ? substr($text, $i - 1, 1) : '';
            if ($before =~ /[<>]/) {
                (my $reader = $simple) =~ s/[<>]\z//;
                # `>( … )` reads what the outer command writes, so the outer command's heredocs are its stdin.
                my @stdin = $before eq '>' ? (@command_docs, @arg_docs, @piped_docs) : ();
                $finish->($simple, 0);
                push @frames, {kind => 'proc', depth => $depth, reader => $reader, stdin => \@stdin, out => [], writes => $before eq '>'};
            } elsif (!command_words($simple) && $simple !~ /[<>]\s*\z/) {
                $open_braces->($simple);
                push @frames, {kind => 'sub', depth => $depth, stdin => [@piped_docs], out => []};
            } else {
                $finish->($simple, 0);
            }
            $simple = '';
            $word_keep = 0;
            $out .= $char;
            $i++;
            next;
        }
        if ($char eq ')') {
            # Finished first: a `{ …; }` ending here closes before the `( … )` around it is matched.
            $finish->($simple, 0);
            my $closes = @frames && ($frames[-1]{depth} || 0) == $depth && $depth;
            $depth-- if $depth;
            if ($closes) {
                my $frame = pop @frames;
                if ($frame->{kind} eq 'proc') {
                    mark(file_reader($frame->{reader}), @{$frame->{out}});
                } else {
                    push @arg_docs, @{$frame->{out}};
                }
                $attached = $frame->{seen} if ($frame->{kind} ne 'proc' || $frame->{writes}) && ($frame->{seen} || 0) > $attached;
            }
            $simple = '';
            $word_keep = 0;
            $out .= $char;
            $i++;
            next;
        }
        if ($char =~ /[;|\n]/ || ($char eq '&' && substr($text, $i - 1, 1) !~ /[<>]/ && substr($text, $i + 1, 1) ne '>')) {
            # `|` and `|&` feed this command's output to the next; the second bar of `||` ends the pipeline.
            my $pipe = $char eq '|' && substr($text, $i - 1, 1) ne '|';
            $finish->($simple, $pipe) unless $char eq "\n" && $continues;
            $simple = '';
            $word_keep = 0;
            if ($pipe && substr($text, $i + 1, 1) eq '&') {
                $out .= '|&';
                $i += 2;
                next;
            }
        } else {
            $simple .= $char eq "\t" ? ' ' : $char;
            $word_keep = 0 if $char =~ /\s/;
        }
        $out .= $char eq "\t" ? ' ' : $char;
        $i++;
    }
    die "Unterminated substitution\n" if $stop;
    $finish->($simple, 0);
    $out .= $flush_inline->();
    return ($out, $i, \@all);
}
