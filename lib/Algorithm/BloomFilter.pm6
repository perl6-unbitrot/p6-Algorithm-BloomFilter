use v6;
use experimental :pack;
use Digest::SHA;

unit class Algorithm::BloomFilter;

has Rat $.error-rate;
has Int $.capacity;
has Int $.key-count;
has Int $.filter-length;
has Int $.num-hash-funcs;
has Num @.salts;
has Buf $.filter;
has Int $.blankvec;

method BUILD(Rat:D :$!error-rate, Int:D :$!capacity) {
    my %filter-settings = self.calculate-shortest-filter-length(
        num-keys   => $!capacity,
        error-rate => $!error-rate,
    );
    $!key-count      = 0;
    $!filter-length  = %filter-settings<length>;
    $!num-hash-funcs = %filter-settings<num-hash-funcs>;
    @!salts          = self.create-salts(count => $!num-hash-funcs);

    # Create an empty filter
    $!filter = Buf.new((for 1 .. $!filter-length { 0 }));

    # Create a blank vector
    $!blankvec = 0;
}

method calculate-shortest-filter-length(Int:D :$num-keys, Rat:D :$error-rate --> Hash[Int]) {
    my Num $lowest-m;
    my Int $best-k = 1;

    for 1 ... 100 -> $k {
        my $m = (-1 * $k * $num-keys) / (log(1 - ($error-rate ** (1 / $k))));

        if (!$lowest-m.defined || ($m < $lowest-m)) {
            $lowest-m = $m;
            $best-k   = $k;
        }
    }

    my Int %result =
        length         => $lowest-m.Int + 1,
        num-hash-funcs => $best-k;
}

method create-salts(Int:D :$count --> Seq) {
    my Num %collisions;

    while %collisions.keys.elems < $count {
        my Num $c = rand;
        %collisions{$c} = $c;
    }

    %collisions.values;
}

method get-cells(Cool:D $key, Int:D :$filter-length, Int:D :$blankvec, Num:D :@salts --> Array[Int]) {
    my Int @cells;

    for @salts -> $salt {
        my Int $vec = $blankvec;
        my Int @pieces = sha1($key ~ $salt).unpack('N*');

        $vec = $vec +^ $_ for @pieces;

        @cells.push: $vec % $filter-length; # push bit-offset
    }

    @cells;
}

method add(::?CLASS:D: Cool:D $key) {

    die "Exceeded filter capacity: {$!capacity}"
        if $!key-count >= $!capacity;

    $!key-count++;

    $!filter[$_] = 1 for self.get-cells(
        $key,
        filter-length => $!filter-length,
        blankvec      => $!blankvec,
        salts         => @!salts,
    );
}

method check(::?CLASS:D: Cool:D $key --> Bool) {
    so $!filter[
        self.get-cells(
            $key,
            filter-length => $!filter-length,
            blankvec      => $!blankvec,
            salts         => @!salts,
        )
    ].all === 1;
}


=begin pod

=head1 NAME

Algorithm::BloomFilter - A bloom filter implementation in Perl 6

=head1 SYNOPSIS

  use Algorithm::BloomFilter;

  my $filter = Algorithm::BloomFilter.new(
    capacity   => 100,
    error-rate => 0.01,
  );

  $filter.add("foo-bar");

  $filter.check("foo-bar"); # True

  $filter.check("bar-foo"); # False with possible false-positive

=head1 DESCRIPTION

Algorithm::BloomFilter is a pure Perl 6 implementation of L<Bloom Filter|https://en.wikipedia.org/wiki/Bloom_filter>, mostly based on L<Bloom::Filter|https://metacpan.org/pod/Bloom::Filter> from Perl 5.

=head1 METHODS

=head2 new(Rat:D :$error-rate, Int:D :$capacity)

Creates a Bloom::Filter instance.

=head2 add(Cool:D $key)

Adds a given key to filter instance.

=head2 check(Cool:D $key) returns Bool

Checks if a given key is in filter instance.

=head1 INTERNAL METHODS

=head2 calculate-shortest-filter-length(Int:D :$num-keys, Rat:D $error-rate) returns Hash[Int]

Calculates and returns filter's length and a number of hash functions.

=head2 create-salts(Int:D :$count) returns Seq[Num]

Creates and returns C<$count> unique and random salts.

=head2 get-cells(Cool:D $key, Int:D :$filter-length, Int:D :$blankvec, Num:D :@salts) returns Array[Int]

Calculates and returns positions in bit vector to check flags.

=head1 AUTHOR

yowcow <yowcow@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2016 yowcow

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
