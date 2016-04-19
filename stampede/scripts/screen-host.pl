#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use autodie;
use Bio::SeqIO;
use Data::Dump 'dump';
use IO::File;
use Getopt::Long;
use Cwd qw(cwd);
use File::Basename qw(basename dirname);
use File::Find::Rule;
use File::Spec::Functions qw(catfile);
use File::Path qw(make_path);
use Pod::Usage;

main();

# --------------------------------------------------
sub main {
    my $accepted_dir = cwd();
    my $rejected_dir = cwd();
    my $fasta_file   = '';
    my $mode_dir     = '';
    my $mode_min     =  1;
    my ($help, $man_page);
    GetOptions(
        'a|accepted:s' => \$accepted_dir,
        'f|fasta=s'    => \$fasta_file,
        'm|mode-dir=s' => \$mode_dir,
        'n|mode-min:i' => \$mode_min,
        'r|rejected:s' => \$rejected_dir,
        'help'         => \$help,
        'man'          => \$man_page,
    ) or pod2usage(2);

    if ($help || $man_page) {
        pod2usage({
            -exitval => 0,
            -verbose => $man_page ? 2 : 1
        });
    };

    unless ($fasta_file) {
        pod2usage('Missing -f fasta_file ');
    }

    unless (-s $fasta_file) {
        pod2usage("Bad fasta_file ($fasta_file)");
    }

    unless ($mode_dir) {
        pod2usage('Missing -m mode_dir ');
    }

    unless (-d $mode_dir) {
        pod2usage("Bad mode_dir ($mode_dir)");
    }

    for my $dir ($accepted_dir, $rejected_dir) {
        make_path($dir) unless -d $dir;
    }

    my @mode_files    = find_mode_files($mode_dir);
    my $out_basename  = basename($fasta_file);
    my $accepted_file = catfile($accepted_dir, $out_basename);
    my $rejected_file = catfile($rejected_dir, $out_basename);
    my $query    = Bio::SeqIO->new(-file => $fasta_file,       -format => 'Fasta');
    my $accepted = Bio::SeqIO->new(-file => ">$accepted_file", -format => 'Fasta');
    my $rejected = Bio::SeqIO->new(-file => ">$rejected_file", -format => 'Fasta');

    printf "Processing FASTA file '%s' to %s host files\n", 
        basename($fasta_file), scalar(@mode_files);

    my @mode_fhs;
    for my $mode_file (@mode_files) {
        push @mode_fhs, IO::File->new($mode_file, 'r');
    }

    my ($num_seen, $num_accepted, $num_rejected) = (0, 0, 0);
    while (my $seq = $query->next_seq) {
        $num_seen++;
        my @modes;
        for my $fh (@mode_fhs) {
            chomp(my $line = $fh->getline());
            my ($read_n, $mode) = split(/\s+/, $line);
            if ($mode >= $mode_min) {
                push @modes, $mode;
            }
        }

        if (@modes) {
            $num_rejected++;
            $rejected->write_seq($seq);
        }
        else {
            $num_accepted++;
            $accepted->write_seq($seq);
        }
    }

    say join "\n",
        "mode min     = $mode_min",
        "num seen     = $num_seen",
        "num accepted = $num_accepted",
        "num rejected = $num_rejected",
        "% rejected   = " . int($num_rejected/$num_seen * 100),
        "accepted     = " . $accepted_file,
        "rejected     = " . $rejected_file,
    ;
}

# --------------------------------------------------
sub find_mode_files {
    my $mode_dir   = shift;
    my @mode_files = File::Find::Rule->file()->in($mode_dir)
                     or die "Found no mode files in mode_dir ($mode_dir)\n";

    my %mode_file;
    for my $mode_file (@mode_files) {
        chomp(my $lc = `wc -l $mode_file`);
        if ($lc =~ /(\d+) \s+ (.+)/xms) {
            $mode_file{ $2 } = $1;
        }
    }

    my $mode = mode(values %mode_file);
    if ($mode == 0) {
        die "No useable mode ($mode) from mode_dir ($mode_dir)\n"; 
    } 

    my @passed = sort grep { $mode_file{ $_ } == $mode } keys %mode_file;

    if (@passed != scalar(keys %mode_file)) {
        warn "Some mode files did not match line count mode '$mode'\n";
    }

    return @passed;
}

# --------------------------------------------------
sub mode {
    my @n = @_ or return;
    my %c;
    map { $c{$_}++ } @n;
    my @sorted = sort { $c{$b} <=> $c{$a} } keys %c;
    return $sorted[0];
}

__END__

# --------------------------------------------------

=pod

=head1 NAME

screen-host.pl - screen host sequences from FASTA files

=head1 SYNOPSIS

  screen-host.pl -f FASTA_FILE -m MODE_DIR -a ACCEPT -r REJECT -n MODE

Required arguments:

  -f|--fasta      FASTA file to screen
  -m|--mode-dir   Directory to mode files for FASTA

Options:

  -q|--accepted   Directory to write accepted sequences (cwd)
  -r|--rejected   Directory to write rejected sequences (cwd)
  -n|--mode-min   Minimum mode value to determine similarity to host (1)
  --help          Show brief help and exit
  --man           Show full documentation

=head1 DESCRIPTION

Reads a "host" file of read IDs, filters these from the FASTA files,
writes to the "out" directory.

=head1 SEE ALSO

perl.

=head1 AUTHOR

Ken Youens-Clark E<lt>kyclark@email.arizona.eduE<gt>.

=head1 COPYRIGHT

Copyright (c) 2015 Hurwitz Lab

This module is free software; you can redistribute it and/or
modify it under the terms of the GPL (either version 1, or at
your option, any later version) or the Artistic License 2.0.
Refer to LICENSE for the full license text and to DISCLAIMER for
additional warranty disclaimers.

=cut
