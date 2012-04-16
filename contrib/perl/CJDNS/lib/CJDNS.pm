package CJDNS;

use Bencode qw(bencode bdecode);
use Carp qw/croak/;
use Digest::SHA2;
use IO::Socket;

# buffer size for reading from teh sawkets.
use constant BUFFER_SIZE => 1024;

our @ISA = qw();
our $VERSION = '0.01';
our $sha2 = new Digest::SHA2 256;

# turn on autoflush for this class.
our $| = 1;

sub new {
    my ($class, $addr, $port, $password) = @_;

    my $self = bless({
        connection => "$addr:$port",
        password => $password,
    }, $class);

    $self->{s} = IO::Socket::INET->new(
        PeerAddr => $addr,
        PeerPort => $port,
        Proto => 'tcp',
        Type => SOCK_STREAM
    );

    unless ($self->_ping) {
        die "Error, cannot ping CJDNS admin service on $self->{connection}\n";
    }

    $self->_make_methods;

    return $self;
}

sub _make_methods {
    my ($self) = @_;
    my $s = $self->s;

    my ($to_decode);
    print $s "d1:q7:invalide";
    while (1) {
        my $data;
        recv($s, $data, BUFFER_SIZE, undef);
        if (length($data)) {
            $to_decode .= $data;
            if (length($data) < BUFFER_SIZE) {
                last;
            }
        }
    }

    my $decoded = bdecode($to_decode);

    # first let's start by loading them as named into the CJDNS namespace.

    foreach my $method_name (keys %{$decoded->{availableFunctions}}) {
        my $prototype = $decoded->{availableFunctions}->{$method_name};
        $self->{capabilities}->{$method_name} = $prototype;

        # This is the code that actually calls the function!
        my $method = sub {
            my ($self, %args) = @_;
            my $s = $self->s;
            my ($to_decode);
            print $s "d1:q6:cookiee";
            while (1) {
                my $data;
                recv($s, $data, BUFFER_SIZE, undef);
                if (length($data)) {
                    $to_decode .= $data;
                    if (length($data) < BUFFER_SIZE) {
                        last;
                    }
                }
            }

            my $dec = bdecode($to_decode);

            my $cookie = $dec->{cookie};

            my $req = {
                q => 'auth',
                aq => $method_name,
                hash => $self->_sha2_hexdigest($self->{password} . $cookie),
                cookie => " $cookie",
                args => \%args,
            };

            # replace $req->{hash} with a hash of the bencoded request.
            my $req_benc = bencode($req);
            $req->{hash} = $self->_sha2_hexdigest($req_benc);

            # then re-encode thusly:
            $req_benc = bencode($req);

            print $s $req_benc;

            my ($to_decode);
            while (1) {
                my $data;
                recv($s, $data, BUFFER_SIZE, undef);
                if (length($data)) {
                    $to_decode .= $data;
                    if (length($data) < BUFFER_SIZE) {
                        last;
                    }
                }
            }
            my $dec = bdecode($to_decode);
            if (ref($dec)) {
                if ($dec->{error}) {
                    croak "[error] CJDNS method '$method_name': $dec->{error}";
                } 
            }
            return $dec;
        };

        # and now it's a method!
        my $full_name = "CJDNS::$method_name";
        *{$full_name} = $method;
    }
}

sub capabilities {
    my ($self) = @_;
    my $return = "CJDNS Administration Protocol Capabilities\n";
    $return .= "------------------------------------------\n";
    foreach my $func (keys %{$self->{capabilities}}) {
        $return .= " $func\n";
        foreach my $attr (keys %{$self->{capabilities}->{$func}}) {
            $return .= "   + $attr: $self->{capabilities}->{$func}->{$attr}->{type} ";

            if ($self->{capabilities}->{$func}->{$attr}->{required}) {
                $return .= "[required]";
            }
            
            $return .= "\n";
        }
        $return .= "\n";
    }
    return $return;
}

sub _sha2_hexdigest {
    my ($self, $string) = @_;
    $sha2->reset();
    $sha2->add($string);
    return $sha2->hexdigest;
}

sub _ping {
    my ($self) = @_;
    my $s = $self->s;

    my $data;
    print $s "d1:q4:pinge";
    recv($s, $data, BUFFER_SIZE, undef);

    if ($data eq "d1:q4:ponge") {
        return 1;
    } else {
        return undef;
    }
}

sub s {
    my ($self) = @_;
    return $self->{s};
}

1;
__END__

=head1 NAME

CJDNS - Perl interface to the CJDNS Administration Interface

=head1 SYNOPSIS

  use CJDNS;
  my $cjdns = CJDNS->new('localhost', '12345', 'abc123');
  printf("CJDNS' routing table is using %d bytes of memory!\n", $cjdns->memory->{bytes});

=head1 DESCRIPTION

Perl interface to the CJDNS Administration system

=head1 SEE ALSO

https://github.com/cjdelisle/cjdns

=head1 AUTHOR

Michael Gregorowicz, E<lt>mikei@mg2.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Michael Gregorowicz

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
