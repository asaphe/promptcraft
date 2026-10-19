#!/usr/bin/env perl
# Names each way a command runs code nobody can read in its text. see: ../destructive-guard/README.md § Hidden code execution
use strict;
use warnings;

my $c = do { local $/; <STDIN> };
$c = '' unless defined $c;
my $lc = lc $c;
my @why;

# An invalid regex dies here, and the guard turns a failed helper into an ask.
my $ns_src = $ENV{DESTRUCTIVE_GUARD_APP_NS};
$ns_src = '^(?!kube-)' unless defined $ns_src && length $ns_src;
my $APP_NS = qr{$ns_src};
my $INTERP = qr{(?:python[\d.]*|pypy3?|node(?:js)?|deno|bun|ruby|irb|perl|php|lua|luajit|java|jshell|groovy|scala|kotlin|go|rscript|julia|elixir|iex|sh|bash|zsh|ash|dash|ksh|fish|busybox|psql|pg_restore|mysql|mariadb|sqlite3|clickhouse(?:-client)?|mongosh|mongo|redis-cli|cqlsh|dagster|dbt|curl|wget|xargs|awk|gawk|env|nohup|timeout|exec|su|sudo)};

sub ns_of {
  my ($flags) = @_;
  return $1 if $flags =~ /(?:^|\s)(?:-n|--namespace)(?:=|\s+)["']?([\w.-]+)/;
  return undef;
}
# No -n means the context's default namespace, which the text cannot name, so it counts as an app namespace.
sub app_ns { my ($ns) = @_; return !defined $ns || $ns =~ $APP_NS }
sub ns_name { my ($ns) = @_; return defined $ns ? "namespace $ns" : "the context's default namespace" }

# 1. Code run inside a cluster workload: it holds that workload's database and cloud credentials.
while ($c =~ /\bkubectl\b([^\n;|&]*?)\s(exec|debug|run|attach)\b([^\n]*)/g) {
  my ($pre, $verb, $rest) = ($1, $2, $3);
  my $ns = ns_of("$pre $rest");
  next unless app_ns($ns);
  if ($verb eq 'debug' || $verb eq 'run') { push @why, "kubectl $verb starts a new pod in " . ns_name($ns); next }
  my ($after) = $rest =~ /\s--\s+(.*)$/;
  if (!defined $after) { push @why, "kubectl $verb into " . ns_name($ns) . " with no command visible"; next }
  my @w = map { my $x = $_; $x =~ s/^["']+|["']+$//g; $x } split ' ', $after;
  shift @w while @w && $w[0] =~ /^(?:[A-Za-z_]\w*=\S*|-\S+|\d+[smh]?)$/;
  my $head = @w ? $w[0] : '';
  $head =~ s{.*/}{};
  push @why, "kubectl $verb runs $head inside " . ns_name($ns) if $head =~ /^$INTERP$/i;
}

# 2. A pod or Job created from a manifest: a copy of a live Deployment's spec carries its credentials and runs any command.
while ($c =~ /\bkubectl\b([^\n;|&]*?)\s(apply|create|replace)\b([^\n;|&]*)/g) {
  my ($pre, $verb, $rest) = ($1, $2, $3);
  my $ns = ns_of("$pre $rest");
  if ($rest =~ /^\s+(job|cronjob)\b/) { push @why, "kubectl create $1 in " . ns_name($ns) if app_ns($ns); next }
  my @files = $rest =~ /(?:-f|--filename)(?:=|\s+)["']?([^\s"']+)/g;
  for my $f (@files) {
    if ($f eq '-') { push @why, "kubectl $verb -f - from stdin into " . ns_name($ns) . ", manifest not visible" if app_ns($ns); next }
    (my $p = $f) =~ s{^~/}{$ENV{HOME}/};
    if ($p =~ /[\$`(]/ || !-e $p) { push @why, "kubectl $verb -f $f into " . ns_name($ns) . ", manifest not readable before it runs" if app_ns($ns); next }
    next unless -f $p && -r $p;
    open my $fh, '<', $p or next;
    my $m = do { local $/; <$fh> };
    close $fh;
    next unless $m =~ /["']?kind["']?\s*:\s*["']?(Pod|Job|CronJob)\b/;
    my $kind = $1;
    my $mns = $ns;
    $mns = $1 if !defined $mns && $m =~ /["']?namespace["']?\s*:\s*["']?([\w.-]+)/;
    push @why, "kubectl $verb creates a $kind from $f in " . ns_name($mns) if app_ns($mns);
  }
}

# 3. Code decoded or downloaded, then run: its text exists only at runtime.
push @why, "decoded text piped into $2" if $lc =~ /\b(base64|xxd|openssl|uudecode|gunzip|zcat|bunzip2|xz|rev)\b[^\n|]*\|\s*(?:sudo\s+)?($INTERP)\b/;
push @why, "downloaded text piped into $2" if $lc =~ /\b(curl|wget|fetch|http|aws\s+s3\s+cp|gsutil\s+cat)\b[^\n|]*\|\s*(?:sudo\s+)?($INTERP)\b/;
push @why, "$1 reads code from a process substitution" if $lc =~ /\b($INTERP)\b[^\n|;&]*<\s*\(\s*(?:curl|wget|base64|cat)\b/;
push @why, "$1 runs a command substitution of $2" if $lc =~ /\b($INTERP)\b[^\n|;&]*\s-(?:c|e|-eval)\s+["']?\$\(\s*(curl|wget|base64|cat|aws)\b/;
if ($lc =~ /b64decode|base64\.(?:standard_|urlsafe_)?b64decode|base64\.decode|atob\s*\(|buffer\.from\([^)]*['"]base64|frombase64string|unhexlify|bytes\.fromhex|codecs\.decode|zlib\.decompress|marshal\.loads|pickle\.loads/
    && $lc =~ /\b(?:exec|eval|compile|system|popen|spawn\w*|function)\s*\(|`|\bsubprocess\b|child_process/) {
  push @why, "code decoded at runtime and then executed";
}

my %seen;
print join("; ", grep { !$seen{$_}++ } @why);
