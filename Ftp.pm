package IO::Ftp;
require 5.005_62;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

use vars qw/@ISA $VERSION/;

$VERSION = 0.01;
our %EXPORT_TAGS = ( 'all' => [ qw(
		new	
		delete
		rename_to
		mdtm
		size
		filename
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();


use File::Basename;
use URI;
use Symbol;
use Net::FTP;
use Carp;


sub new {
	my ($src, $mode, $uri_string, %args) = @_;
	my $class = ref $src || 'IO::Ftp';
	if (ref $src and not $src->isa('IO::Ftp')) {
		carp "Can't make an IO::FTP from a ", ref $src;
		return;
	}

	my $uri = URI->new('ftp:' . $uri_string);

	my $ftp;
	if (ref $src and not $uri->host) {
		if ($src->connected) {
			warn "Can't reuse host with open connection";
			return;
		}
		$ftp = ${*$src}{'io_ftp_ftp'};
	} else {		
		$ftp = Net::FTP->new(
			$uri->host, 
			Port => ($uri->port || 80),
			Debug => $args{DEBUG},
			Timeout => $args{Timeout},
			BlockSize => $args{BlockSize},
			Passive => $args{Passive},
		);
	}
	
	unless ($ftp) {
		carp "Can't connect to host ", $uri->host;
		return;
	}
	
	my $self = __open($ftp, $mode, $uri, %args);
	return unless $self;
	
	${*$self}{'io_ftp_ftp'} = $ftp;

	return bless $self, $class;
}

sub __open {
	my ($ftp, $mode, $uri, %args) = @_;

	my $id = $uri->user || 'anonymous';
	my $pwd = $uri->password || 'anon@anon.org';
	
	$ftp->login($id, $pwd);
	fileparse_set_fstype($args{OS}) if $args{OS};
	
	my ($file, $path) = fileparse($uri->path);
	warn "File: $file, Path: $path" if $args{DEBUG};
	
	foreach ('/', split '/', $path) {
		unless ($ftp->cwd($_)) {
			warn "Can't cwd to $_";
			return;
		}
	}
	if ($args{type}) {
		unless ($args{type} =~ /^[ai]$/i) {
			carp "Invalid type: $args{type}";
			return;
		}
		unless ($ftp->type($args{type}) ) {
			carp "Can't set type $args{type}: ", $ftp->message;
		}
	}

	if ($mode eq '<<') {
		$file = __find_file($ftp, $file);
		return unless $file;
	}

	# cache these in case user wants initial values.  Can't get them once the data connection is open.
	my $size = $ftp->size($file);
	my $mdtm = $ftp->mdtm($file);
	
	
	my $dataconn;
	if ($mode eq '<' or $mode eq '<<') {
		$dataconn = $ftp->retr($file);
	} elsif ($mode eq '>') {
		$dataconn = $ftp->stor($file);
	} elsif ($mode eq '>>') {
		$dataconn = $ftp->appe($file);
	} else {
		carp "Invalid mode $mode";
		return;
	}

	unless ($dataconn) {
		carp "Can't open $file: ", $ftp->message ;
		return;
	}

	# we want to be a subclass of the dataconn, but its class is dynamic.
	push @ISA, ref $dataconn;
	
	${*$dataconn}{'io_ftp_file'} = $file;
	${*$dataconn}{'io_ftp_size'} = $size;
	${*$dataconn}{'io_ftp_mdtm'} = $mdtm;
	
	return $dataconn;
}

sub __find_file {
	my ($ftp,$pattern) = @_;

	my @files = $ftp->ls($pattern);	
	return $files[0];
}


sub filename {
	my $self = shift;
	return ${*$self}{'io_ftp_file'};	
}

### allow shortcuts to Net::FTP's rename and delete, but only if data connection not open.  OTW we'll hang.

sub rename_to {
	my ($self, $new_name) = @_;
	return if $self->connected;
	
	my $ret = ${*$self}{'io_ftp_ftp'}->rename(${*$self}{'io_ftp_file'}, $new_name);
	${*$self}{'io_ftp_file'} = $new_name;
	return $ret;
}

sub delete {
	my ($self) = @_;
	return if $self->connected;
	
	return ${*$self}{'io_ftp_ftp'}->delete(${*$self}{'io_ftp_file'});
}


### return cached stats if connected, or real ones if connection closed.

sub mdtm {
	my ($self) = @_;
	return ${*$self}{'io_ftp_mdtm'} if $self->connected;
	
	return ${*$self}{'io_ftp_ftp'}->mdtm(${*$self}{'io_ftp_file'});
}

sub size {
	my ($self) = @_;
	return ${*$self}{'io_ftp_size'} if $self->connected;
	
	return ${*$self}{'io_ftp_ftp'}->size(${*$self}{'io_ftp_file'});
}


1;


=head1 NAME

IO::Ftp - A simple interface to Net::FTP's socket level get/put

=head1 SYNOPSIS


 use IO::Ftp;
 
 my $out = IO::Ftp->new('>','//user:pwd@foo.bar.com/foo/bar/fu.bar', TYPE=>'a');
 my $in = IO::Ftp->new('<','//foo.bar.com/foo/bar/fu.bar', TYPE=>'a');	#anon access example

  
 while (<$in>) {
 	s/foo/bar/g;
 	print $out;
 }
 
 close $in;
 close $out;

 ---
 
while (my $in = IO::Ftp->new('<<','//foo.bar.com/foo/bar/*.txt', TYPE=>'a') {
	print "processing ",$in->filename, "\n";
	#...
	$in->close;
	$in->delete;
}


=head1 DESCRIPTION

Blah blah blah.


=head2 EXPORT

None by default.

=head2 REQUIRES

L<Net::FTP>
L<File::Basename>
L<URI>
L<Symbol>

=head1 AUTHOR

Mike Blackwell <maiku41@anet.com>


=head1 SEE ALSO

Net::FTP
perl(1).

=cut
