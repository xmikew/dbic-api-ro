use Moose::Role;
use JSON qw(encode_json);
use List::Util;
use Data::Dumper;

has 'allow_resultsets' => (
        isa => 'ArrayRef|Str',
        is => 'rw',
        required => 1,
        builder => '_build_allow_resultsets'
);

# The key we'll look for in the
# JSON data to see what resultset's to apply
has 'resultset_key' => (
        isa => 'Str',
        is => 'rw',
        required => 1,
        default => sub { 'rsets' }
);

# Allows doing a list without any serach parameters
# Basically pulls in the entire table
has 'allow_full_listing' => (
        isa => 'Bool',
        is => 'rw',
        required => 1,
        default => sub { 0 }
);

=head2 list_munge_parameters

Override the function from DBIC::API::*
This function is called during the request processing of a DBIC::API call.

=cut

around 'list_munge_parameters' => sub {
        my ($orig,$self,$c) = @_;
        my $params = $c->req->params;
        my $key = $self->resultset_key;
        my $rsets;
        if ($params->{$key}) {
                        $c->log->debug("Rset Methods: " . Dumper($params->{$key}));
                        try {
                                        $rsets = decode_json($params->{$key});
                        } catch {
                                        $c->error("Failed to decode json for resultset parameters");
                                        error_json($c, undef, "Failed to decode json for result parameters");
                                        $c->detach;
                        };
        }

        foreach my $rs_method (keys %$rsets) {
                        if ( any { $_ eq $rs_method } @{$self->allow_resultsets} ) {
                                        my $rs = $c->req->current_result_set;
                                        # scalar forces a result_set method returned when applying the rset.
                                        $c->req->_set_current_result_set(
                                                        scalar( $rs->$rs_method($rsets->{$rs_method}) )
                                        );
                                        $c->log->debug("Applying $rs_method to result set");
                        } else {
                                        error_json($c, 400, "Invalid result set method requested: $rs_method");
                                        $c->detach;
                        }
        }

        # Don't allow just hitting the index page, we don't want to be able to return ALL records. Some parameters
        # are required
        if (!$self->allow_full_listing && scalar(keys %$params) < 1) {
                        error_json($c, undef, "No search parameters provided, returning all records for a resource is not supported.");
                        $c->detach;
        }

        # if we override any other list_munge_parameter defined, call them now.
        return $self->$orig($c);
};


=head2 method modifiers

All these functions inside of API::REST are overridden and return 405 instead of
calling their regular methods

=cut


=head2 update_or_create_objects

overrides C::C::DBIC::API update_or_create_objects to take a post in a
read only controller. This allows posting search parameters instead of
just in the GET parameters. This ends up just calling list_objects in
C::C::DBIC::API. This doesnt' currently work since deserialize assumes
anything with body data is a create/update request

=cut

around 'update_or_create_objects' => sub {
        my ($orig, $self, $c) = @_;
        return $self->list_objects($c);
};

=head2 update_or_create_one_object

=head2 delete_many_objects

=head2 delete_one_object

All these functions will return 405 unimplmeneted error in a read-only controller

=cut

around ['update_or_create_one_object',
        'delete_many_objects',
        'delete_one_object'
] => sub {
        my ( $class, $self, $c ) = @_;
        $self->return_unimplemented($c);
};


=head2 return_unimplemented

Returns 405 unimplemented and json error for any POST, PUT, DELETE functions
in ::API

=cut

sub return_unimplemented {
        my ( $self, $c ) = @_;
        error_json($c, 405, ('Unimplemented/method not allowed'));
        $c->detach();
}

=head2 error_json

return provided error message and json encoded data

=cut

sub error_json {
                my ($c,$code,@msg) = @_;
                $code ||= 400;
                $c->res->status($code);
                $c->res->content_type('application/json');
                $c->res->body(
                                encode_json({'success' => 0, messages => \@msg})
                );
                return 1;
}

=head2 _build_allow_resultsets

allow_resultsets can be an arrayref or a Str.
If it's a string, we split it by , into an arrayref during build time.
So we should always have an arrayref when using it. Str just allows
csv to be used in a config file. This is called after the object construction

=cut

sub _build_allow_resultsets {
        my ($self) = @_;
        my $rsets = $self->allow_resultsets;

        # set as Str but not an arrayref
        if (defined($rsets) && !ref($rsets)) {
                $rsets =~ s/\s+//g;
                $self->allow_resultsets( [ split(',', $rsets) ] );
        }
        return [] if !defined($rsets);
}

1;
