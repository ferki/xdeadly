package XDeadly::Post;
use Mojo::Base 'Mojo::Message';

our $VERSION = '0.01';

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::Single;

use Time::Local qw(timegm);
use XDeadly::Article;
use XDeadly::Comment;

use Carp;
use File::Spec::Functions qw/ canonpath catdir catfile /;
use File::Path qw/ make_path /;

has content => sub {
    my ($self) = @_;

    $self->content( Mojo::Content::Single->new );

    if ($self->has_path and -e $self->path) {
        my $file = Mojo::Asset::File->new( path => $self->path );
        $self->parse( $file->slurp );
    }

    return $self->content;
};

has '_epoch' => sub {
    my ($self) = @_;
    return unless $self->headers->date;
    return _parse_ctime( $self->headers->date );
};

has level => 0;
has is_article => 0;

has 'id';
has 'filename' => 'post';
has 'data_dir';

sub parse {
    my ( $self, $chunk ) = @_;

    $self->content->on( body => sub {
        my $content = shift;
        my $headers = $content->headers;

        $headers->content_length( length $content->{pre_buffer} )
            unless $headers->content_length;
    } );

    return $self->SUPER::parse($chunk);
}

sub _parse_ctime {
    my ($string) = @_;

    my %months = (
        Jan => 0,
        Feb => 1,
        Mar => 2,
        Apr => 3,
        May => 4,
        Jun => 5,
        Jul => 6,
        Aug => 7,
        Sep => 8,
        Oct => 9,
        Nov => 10,
        Dec => 11,
    );

    my ($wday, $mname, $day, $time, $year, $extra) = split /\s+/xms, $string;
    croak "Invalid date [$string]" if $extra;

    my ($h, $m, $s) = split /:/xms, $time;

    return timegm( $s, $m, $h, $day, $months{$mname}, $year );
};

=head3 dir

The working directory where we store our files.

Should be data_dir/id

=cut

sub dir {
    my ($self) = @_;
    croak('data_dir and id required') unless $self->data_dir and $self->id;
    return canonpath( catdir $self->data_dir, split '/', $self->id );
}

=head3 has_path

A check whether we can calculate the path

=cut

sub has_path {
    my ($self) = @_;
    return $self->id and $self->data_dir
}

=head3 path

The full path to the content of the post.

Built from data_dir/id/filename

=cut

sub path {
    my ($self) = @_;
    return catfile $self->dir, $self->filename;
}

=head3 save( data_dir => $data_dir, id => $id )

saves the file, optionally takes data_dir and id parameters

=cut

sub save {
    my ($self, %args) = @_;

    $self->id( $args{id} )             if $args{id};
    $self->data_dir( $args{data_dir} ) if $args{data_dir};

    croak("Cannot save without a path") unless $self->has_path;

    my $file = Mojo::Asset::Memory->new();
    $file->add_chunk( $self->to_string );

    make_path $self->dir;
    $file->move_to($self->path);

    return $self;
}

sub articles {
    my ( $self, $data_dir ) = @_;
    return [ $self->_load_articles($data_dir) ];
};

sub _load_articles {
    my ( $self, $dir ) = @_;

    opendir my $dh, $dir or croak "Couldn't opendir $dir: $!";
    my @articles = map { $self->_load_article( $dir, $_ ) }
        grep { -d catdir( $dir, $_ ) }    # only files that exist
        sort { $b <=> $a }                # newest to oldest
        grep {/^\d+$/xms}                 # Could probably be more accurate
        readdir $dh;
    closedir $dh or croak "Couldn't closedir $dir: $!";

    return @articles;
}

sub _load_article {
    my ( $self, $data_dir, $id ) = @_;
    XDeadly::Article->new( data_dir => $data_dir, id => $id );
}


# We don't actually have a start_line
sub extract_start_line {1}

sub get_start_line_chunk {
    my ( $self, $offset ) = @_;

    # need start_buffer to be defined, should only ever be the empty string
    $self->{start_buffer} //= q{};

    $self->emit( progress => 'start_line', $offset );
    return substr $self->{start_buffer}, $offset, 131_072;
}


1;