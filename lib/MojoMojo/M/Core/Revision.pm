package MojoMojo::M::Core::Revision;

use strict;
use base 'Catalyst::Base';
use Time::Piece;
use utf8;

__PACKAGE__->has_a(
    created => 'Time::Piece',
    inflate => sub {
  Time::Piece->strptime( shift, "%Y-%m-%dT%H:%M:%S" );
    },
    deflate => 'datetime'
);

# this should probably be re-defined here...
sub formatted_diff {
    return MojoMojo::M::Core::Page::formatted_diff(@_);
}

# this should be removed; don't know if it will even work
sub formatted_content {
    #return MojoMojo::M::Core::Page::formatted_content(@_);
    return MojoMojo::M::Core::Content->formatted(@_);
}

# create_proto: create a "proto revision" that may
# be the basis for a new revision

sub create_proto
{
    my ($class, $page) = @_;
    my %proto_rev;
    my @columns = __PACKAGE__->columns;
    eval { $page->isa('MojoMojo::M::Core::Page') };
    if ($@)
    {
        # assume page is a simple "proto page" hashref
        %proto_rev = map { $_ => $page->{$_} } @columns;
        $proto_rev{version} = 1;
        $proto_rev{path_string} = $page->{path_string};
    }
    else
    {
        my $revision = $page->revision;
        %proto_rev = map { $_ => $revision->$_ } @columns;
        @proto_rev{qw/ creator created /} = (undef) x 2;
        $proto_rev{version}++;
        $proto_rev{path_string} = $page->path_string;
    }
    return \%proto_rev;
}

sub release_new
{
    my ($class, %args) = @_;
    my ($proto_rev, $path, $proto_pages) = @args{qw/ proto_rev path proto_pages /};
    my @columns = __PACKAGE__->columns;

    my $parent;

    # if there are any proto pages, the new revision will be at the end of the path
    if (@$proto_pages > 1)
    {
         # create the missing parent pages
	pop @$proto_pages;
	for my $proto_page (@$proto_pages)
	{
	    $parent ||= $path->[@$path - 1];
             # since SQLite doesn't support sequences, just cheat
             # for now and get the next id by creating a page record
	    my $page = MojoMojo::M::Core::Page->create({ parent => $parent->id });
             my %rev_data = map { $_ => $proto_page->{$_} } @columns;

	    #@rev_data{qw/ page parent parent_version /} = ( $page->id, $page->parent->id, $page->parent->version );
             @rev_data{qw/ page version parent parent_version /} = ( $page->id, 1, $page->parent->id, $page->parent->version );

             # set content to undef:
	    #my $content = MojoMojo::M::Core::Content->create({ creator => 1, body => $rev_data{content} });
	    #$rev_data{content} = $content->id;

	    my $revision = __PACKAGE__->create( \%rev_data );
	    for ( $page->columns )
	    {
		next if $_ eq 'id';
		if ($_ eq 'creator')
		{
		    # ugly hack just for now
		    $page->creator( 1 );
		    next;
		}
		if ($_ eq 'content')
		{
		    $page->$_( undef );
		    next;
		}
		$page->$_( $revision->$_ );
	    }
             $page->update;
             push @$path, $page;
             $parent = $page;
	}
    }
    # Now the last page in the path may be the parent or the previous version
    # of the page we're updating. We should be able to determine this by checking
    # for a "page" page id in the proto rev. May need stronger checking later...
    my $last_page = $path->[@$path - 1];
    my $page;
    unless ($parent)
    {
         if (defined $proto_rev->{page} && $proto_rev->{page} == $last_page->id)
	{
             # we're revising an existing page
	    $parent = $path->[@$path - 2];
             $page = $last_page;
	}
         elsif ($proto_rev->{depth} == ($last_page->depth + 1) && $proto_rev->{page} eq undef)
	{
             # we're creating a new page
	    $parent = $last_page;
	}
         else
	{
	    # something is seriously wrong
             die "Cannot determine what page to create for proto rev page " . $proto_rev->{path_string};
	}
    }
    unless ($page)
    {
	$page = MojoMojo::M::Core::Page->create({ parent => $parent->id });
    }
    my %rev_data = map { $_ => $proto_rev->{$_} } @columns;
    #@rev_data{qw/ page parent parent_version /} = ( $page->id, $page->parent->id, $page->parent->version );
    @rev_data{qw/ page parent parent_version /} = ( $page->id, $parent->id, $parent->version );
    my $content = MojoMojo::M::Core::Content->create({ creator => 1, body => $rev_data{content} });
    $rev_data{content} = $content->id;
    my $revision = __PACKAGE__->create( \%rev_data );
    for ( $page->columns )
    {
        next if $_ eq 'id';
        if ($_ eq 'creator')
        {
             # ugly hack just for now
	    $page->creator( 1 );
             next;
        }
        if ($_ eq 'content')
        {
            my $id = (ref $revision->$_ ? $revision->$_->id : undef);
            $page->$_( $id );
            next;
        }
        $page->$_( $revision->$_ );
    }
    $page->update;
}

1;