#!/usr/bin/perl -w

$spim_path = 'spim';

# spimp - SPIM Preprocessor
# Adds support for various C-like preprocessing features in spim/mips

# Author: Nicholas Berridge-Argent 2018
# Version 1

# Expand binary file into .byte definition
# Args: BinaryExpand (binary file) (source file and line)
# Returns string to be inserted into file
sub BinaryExpand {
    if (!(open FB, '<:raw', $_[0])) {
        print "spimp: $_[1]: Could not expand binary file $_[0]\n";
        exit 1;
    }
    $binary = "$_[0]:\n";
    $size = 0;
    $readin = 0;
    while (($readin = read FB, my $bytes, 16) > 0) {
        $binary .= " .byte ";
        @binchunk = unpack "C$readin", $bytes;
        for ($i = 0; $i < @binchunk; $i++) {
            if ($i == $#binchunk) {
                $binary .= "$binchunk[$i]\n";
            } else {
                $binary .= "$binchunk[$i], ";
            }
        }
        $size += $readin;
    }
    $binary .= "\n$_[0]_size:\n  .word $size\n\n";
    close FB;
    return $binary;
}

@include_stack = ();

# Process a MIPS source file, including all #DEFINEs, #INCLUDEs and
# #BINARYs
# Args: ProcessMIPSFile (source file) (including file) (including line)
# Assumes output is opened as FO
sub ProcessMIPSFile {
    for $f (@include_stack) {
        if ($f eq $_[0]) {
            print "spimp: $_[1] line $_[2]: Trying to INCLUDE $_[0] which has already been included. Skipping\n";
            return;
        }
    }

    push @include_stack, $_[0];

    $r = open my $file, '<', $_[0];
    if (!$r) {
        print "spimp: $_[1] line $_[2]: Could not open file $_[0]\n";
        exit 1;
    }

    local %defines = ();
    local $line_no = 0;

    while ($line = <$file>) {
        $line_no++;

        # Substitute any existing #DEFINEs
        for $f (keys %defines) {
            if (!($line =~ m/^#\s*DEFINE/)) {
                $line =~ s/$f/$defines{$f}/g;
            }
        }

        print FO $line;
        chomp $line;

        # Expand any #DEFINEs from this point on
        if ($line and $line =~ m/^#\s*DEFINE\s+([^\s]*)\s+([^\s]*)/) {
            if ($defines{$1}) {
                print "spimp: $_[0] line $line_no: Warning, redefinition of $1 from $defines{$1} -> $2\n";
            }
            $defines{$1} = $2;
        }

        # Expand any #INCLUDEs
        if ($line and $line =~ m/^#\s*INCLUDE\s+<([^\s]*)>/) {
            ProcessMIPSFile("$1", "$_[0]", "$line_no");
            print FO "\n";
        }

        # Expand any #BINARYs
        if ($line and $line =~ m/^#\s*BINARY\s+<([^\s]*)>/) {
            $biline = BinaryExpand("$1", "$ARGV[0] line $line_no");
            print FO $biline;
            print FO "\n";
        }
    }

    close $file;
}

if (@ARGV == 0 || (@ARGV == 1 && $ARGV[0] =~ m/^-/)) {
    print "spimp: No input file\n";
    print "Usage: $0 [flags] (mips source) [output file]\n";
    exit 1;
}

$flag_help = 0;
$flag_no_run = 0;

# Process flags
if ($ARGV[0] =~ m/^-/) {
    if ($ARGV[0] =~ m/\?/) {
        $flag_help = 1;
    }
    if ($ARGV[0] =~ m/p/) {
        $flag_no_run = 1;
    }
}

if ($flag_help) {
    print "Usage: $0 [flags] (mips source) [output file]\n";
    print "Flags: -? - Displays this help information\n";
    print "       -p - Preprocess only, do not run the file\n";
}

$oname = "mips.out";
if ($ARGV[1]) {
    $oname = $ARGV[1];
}

if (!(open FO, '>', $oname)) {
    print "spimp: Could not open output file $oname\n";
    exit 1;
}

print ">>> Processing to $oname...\n";

if ($ARGV[0] =~ m/^-/) {
    ProcessMIPSFile($ARGV[1], "cmd", ""); 
} else {
    ProcessMIPSFile($ARGV[0], "cmd", "");
}

close FO;

if (!$flag_no_run) {
    print ">>> Running...\n";
    system "$spim_path", "-f", "$oname";
}
