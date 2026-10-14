import Foundation

/// Streams complete console output while retaining only a bounded on-disk log.
enum TerminalOutputRelay {
    static let executable = URL(fileURLWithPath: "/usr/bin/perl")
    static let pipelineStatus = """
    typeset -a upkeep_pipeline_status=("${pipestatus[@]}")
    upkeep_status=${upkeep_pipeline_status[1]}
    if (( upkeep_status == 0 )); then upkeep_status=${upkeep_pipeline_status[2]}; fi
    """

    static func arguments(output: URL, append: Bool, maximumBytes: Int = 16 * 1_024 * 1_024) -> [String] {
        ["-e", program, "--", output.path, append ? "1" : "0", String(max(64, maximumBytes))]
    }

    private static let program = #"""
    use strict;
    use warnings;
    my ($path, $append, $limit) = @ARGV;
    open(my $log, $append && -e $path ? '+<' : '+>', $path) or die "Cannot open command log: $!\n";
    binmode(STDIN); binmode(STDOUT); binmode($log);
    my $position = sysseek($log, 0, 2);
    defined($position) or die "Cannot seek command log: $!\n";
    my $truncated = 0;
    sub write_all {
        my ($handle, $data) = @_;
        my $offset = 0;
        while ($offset < length($data)) {
            my $written = syswrite($handle, $data, length($data) - $offset, $offset);
            defined($written) && $written > 0 or die "Cannot write command output: $!\n";
            $offset += $written;
        }
    }
    while (1) {
        my $count = sysread(STDIN, my $buffer, 8192);
        defined($count) or die "Cannot read command output: $!\n";
        last if $count == 0;
        write_all(\*STDOUT, $buffer);
        next if $truncated;
        my $remaining = $limit - $position;
        if ($remaining > 0) {
            my $accepted = substr($buffer, 0, $remaining);
            write_all($log, $accepted);
            $position += length($accepted);
        }
        if ($count > $remaining) {
            my $marker = "\n[Command output truncated]\n";
            my $end = $limit - length($marker);
            truncate($log, $end) or die "Cannot bound command log: $!\n";
            defined(sysseek($log, $end, 0)) or die "Cannot seek command log: $!\n";
            write_all($log, $marker);
            $truncated = 1;
        }
    }
    close($log) or die "Cannot close command log: $!\n";
    """#
}
