package WWW::Sherdog::BaseObject;

use strict;
use warnings;
use Carp;
use URI;
use Furl;

our $VERSION = '0.01';

sub _delayed_accessors {
    my $class = shift;
    no strict 'refs'; ## no critic
    for my $method (@_) {
        *{"$class\::$method"} = sub {
            my $self = shift;
            if (defined $_[0]) {
                $self->{$method} = $_[0];
            }
            elsif (!defined $self->{$method} && !$self->is_crawled) {
                $self->crawl;
            }
            return $self->{$method};
        };
    }
}

sub new {
    my $class = shift;
    my $self = bless +{
        __crawled => 0,
    }, $class;
    my %args = ref($_[0]) eq 'HASH' ? %{$_[0]} : @_;
    for my $method (keys %args) {
        $self->$method($args{$method});
    }
    return $self;
}

sub _ua {
    my $self = shift;
    unless ($self->{_ua}) {
        (my $agent = __PACKAGE__) =~ s/::[^:]+$//;
        $self->{_ua} = Furl->new(
            agent   => join('/', $agent, $VERSION),
            timeout => 10,
        );
    }
    return $self->{_ua};
}

sub is_crawled { return shift->{__crawled}     }
sub crawled    {        shift->{__crawled} = 1 }

sub _obj_type {
    my $self = shift;
    my $class = ref($self) || $self;
    my($obj_type) = $class =~ m{([^:]+)$};
    return lc($obj_type);
}

sub _guess_url {
    my $self = shift;
    if (my $link = $self->link) {
        return $link;
    }
    my $path = $self->path;
    unless ($path) {
        my $obj_type = $self->_obj_type;
        my $name = $self->name;
        my $id   = $self->id;
        if ($name && $id) {
            $name =~ s/\s+/-/g;
            $path = join '-', $name, $id;
            $self->path($path);
        }
        else {
            croak "Cannot guess url for the $obj_type from passed information.";
        }
    }
    my $link = URI->new_abs($path, 'http://www.sherdog.com/')->as_string;
    $self->link($link);
    return $link;
}

sub crawl {
    my $self = shift;
    my $class = ref($self) || $self;

    my $url = $self->_guess_url;
    my $r = $self->_ua->get($url);
    unless ($r->is_success) {
        carp $r->status_line;
        return;
    }
    my $type = $self->_obj_type;
    my $method = 'crawl_' . $type;
    my $res = $self->$method($r->content);
    $self->_fixup_data($res);
    $self->crawled;
    return $res;
}

sub _fixup_data { croak '_fixup_data() is an abstract method' }

1;
