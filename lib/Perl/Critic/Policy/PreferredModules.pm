package Perl::Critic::Policy::PreferredModules;

use strict;
use warnings;

use parent 'Perl::Critic::Policy';

use Perl::Critic::Utils qw{ :severities :classification :ppi $SEVERITY_MEDIUM $TRUE $FALSE };

use Perl::Critic::Exception::AggregateConfiguration ();
use Perl::Critic::Exception::Configuration::Generic ();

use Config::INI::Reader ();

sub supported_parameters {
    return (
        {
            name        => 'config',
            description => 'Config::INI file listing recommendations.',
            behavior    => 'string',
        },
    );
}

use constant default_severity => $SEVERITY_MEDIUM;
use constant applies_to       => 'PPI::Statement::Include';

use constant optional_config_attributes => qw{ prefer reason severity message for };

# VERSION
# ABSTRACT: Provide custom package recommendations

sub initialize_if_enabled {
    my ( $self, $config ) = @_;

    my $cfg_file = $config->get('config') // '';
    $cfg_file =~ s{^~}{$ENV{HOME}};

    $self->{_is_enabled} = !! $self->_parse_config($cfg_file);

    return $TRUE;
}

sub _throw {
    my ( $self, $msg ) = @_;

    Perl::Critic::Exception::Configuration::Generic->throw(
        message => __PACKAGE__ . ' ' . ( $msg // 'Unknown Error' ),
    );
}

sub _parse_config {
    my ( $self, $cfg_file ) = @_;

    if ( !length $cfg_file ) {
        return;
    }

    if ( !-e $cfg_file ) {
        $self->_throw(qq[config file '$cfg_file' does not exist.]);
    }

    my $content;
    {
        local $/;
        open my $fh, '<', $cfg_file
            or return $self->_add_exception(qq[Cannot open config file '$cfg_file': $!]);
        $content = <$fh>;
    }

    my $preferred_cfg;
    eval { $preferred_cfg = Config::INI::Reader->read_string($content); 1 } or do {
        $self->_throw(qq[Invalid configuration file $cfg_file]);
    };

    my %valid_opts = map { $_ => 1 } optional_config_attributes();
    my $errors     = Perl::Critic::Exception::AggregateConfiguration->new();

    # Config::INI uses '_' for the root/default section — skip it
    delete $preferred_cfg->{'_'};

    foreach my $pkg ( sort keys %$preferred_cfg ) {
        my $setup = $preferred_cfg->{$pkg};

        foreach my $opt ( keys %$setup ) {
            next if $valid_opts{$opt};
            $errors->add_exception(
                Perl::Critic::Exception::Configuration::Generic->new(
                    message => __PACKAGE__ . " Invalid configuration - Package '$pkg' is using an unknown setting '$opt'",
                )
            );
        }

        if ( defined $setup->{severity} ) {
            my $sev = $setup->{severity};
            if ( $sev !~ /\A[1-5]\z/ ) {
                $errors->add_exception(
                    Perl::Critic::Exception::Configuration::Generic->new(
                        message => __PACKAGE__ . " Invalid configuration - Package '$pkg' has invalid severity '$sev' (must be 1-5)",
                    )
                );
            }
        }

        if ( defined $setup->{for} ) {
            my @functions = grep { length } split m{[\s,]+}, $setup->{for};
            if ( !@functions ) {
                $errors->add_exception(
                    Perl::Critic::Exception::Configuration::Generic->new(
                        message => __PACKAGE__ . " Invalid configuration - Package '$pkg' has an empty 'for' list",
                    )
                );
            }
            $setup->{_for_functions} = \@functions;
        }
    }

    die $errors if $errors->has_exceptions();

    $self->{_cfg_preferred_modules} = $preferred_cfg;

    return 1;
}

# Return the list of names explicitly imported by an include statement,
# e.g. `use Foo qw{ bar baz }` or `use Foo 'bar', 'baz'`.
sub _imported_names {
    my ( $self, $elem ) = @_;

    my @names;

    foreach my $arg ( $elem->arguments ) {
        if ( $arg->isa('PPI::Token::QuoteLike::Words') ) {
            push @names, $arg->literal;
        }
        elsif ( $arg->isa('PPI::Token::Quote') ) {
            push @names, $arg->string;
        }
    }

    return @names;
}

# Look for calls to any of @functions anywhere in the document, either as a
# plain function call or fully qualified as $module::function.
sub _document_calls_any {
    my ( $self, $elem, $module, @functions ) = @_;

    my $doc = $elem->top or return $FALSE;
    return $FALSE unless $doc->isa('PPI::Document');

    my %wanted = map { ( $_ => 1, "${module}::$_" => 1 ) } @functions;

    my $words = $doc->find( sub { $_[1]->isa('PPI::Token::Word') && $wanted{ $_[1]->content } } ) or return $FALSE;

    foreach my $word (@$words) {
        return $TRUE if is_function_call($word);
    }

    return $FALSE;
}

# A `for` entry restricts the preference to the listed functions: the module is
# only reported when one of them is actually pulled in or called.
sub _matches_for {
    my ( $self, $elem, $module, $setup ) = @_;

    my $functions = $setup->{_for_functions};
    return $TRUE unless $functions && @$functions;

    my %wanted = map { $_ => 1 } @$functions;

    foreach my $name ( $self->_imported_names($elem) ) {
        return $TRUE if $wanted{$name};
    }

    return $self->_document_calls_any( $elem, $module, @$functions );
}

sub violates {
    my ( $self, $elem ) = @_;

    return () unless $self->{_is_enabled};
    return () unless $elem;

    # 'no Module' unloads/disables — not a use violation
    my $type = $elem->type;
    return () if defined $type && $type eq 'no';

    my $module = $elem->module;

    return () unless defined $module;

    my @violations;

    if ( my $setup = $self->{_cfg_preferred_modules}->{$module} ) {
        push @violations, $self->_build_violation( $module, $setup, $elem );
    }

    # Also check modules passed as arguments to 'use parent' / 'use base'
    if ( $module eq 'parent' || $module eq 'base' ) {
        for my $parent_mod ( $self->_extract_parent_modules($elem) ) {
            next unless my $setup = $self->{_cfg_preferred_modules}->{$parent_mod};
            push @violations, $self->_build_violation( $parent_mod, $setup, $elem );
        }
    }

    return @violations;
}

sub _build_violation {
    my ( $self, $module, $setup, $elem ) = @_;

    return () unless $self->_matches_for( $elem, $module, $setup );

    my $desc = qq[Using module $module is not recommended];
    my $expl = $setup->{reason} // $desc;

    if ( defined $setup->{message} ) {
        $desc = $setup->{message};
    }
    elsif ( my $prefer = $setup->{prefer} ) {
        $desc = "Prefer using module $prefer over $module";
    }

    if ( my $functions = $setup->{_for_functions} ) {
        $desc .= ' for ' . join( ', ', @$functions );
    }

    if ( my $sev = $setup->{severity} ) {
        local $self->{_severity} = $sev;
        return $self->violation( $desc, $expl, $elem );
    }

    return $self->violation( $desc, $expl, $elem );
}

sub _extract_parent_modules {
    my ( $self, $elem ) = @_;

    my @modules;
    for my $child ( $elem->schildren ) {
        if ( $child->isa('PPI::Token::Quote') ) {
            my $val = $child->string;
            push @modules, $val if $val =~ /\A[A-Za-z_]\w*(?:::\w+)*\z/;
        }
        elsif ( $child->isa('PPI::Token::QuoteLike::Words') ) {
            push @modules, grep { /\A[A-Za-z_]\w*(?:::\w+)*\z/ } $child->literal;
        }
    }
    return @modules;
}

1;

__END__

=pod

=encoding UTF-8

=head1 DESCRIPTION

Every project has its own rules for preferring specific packages over others.

This Policy tries to be `un-opinionated` and let the user provide a module
preferences with an explanation and/or suggested alternative.

=head1 MODULES

=head1 CONFIGURATION

To use L<Perl::Critic::Policy::PreferredModules> you have first to enable it in your
 F<.perlcriticrc> file by providing a F<preferred_modules.ini> configuration file:

    [PreferredModules]
    config = /path/to/preferred_modules.ini
    # you can also use '~' in the path for $HOME
    #config = ~/.preferred_modules

The  F<preferred_modules.ini> file is using the L<Config::INI> format and can looks like this

    [Do::Not::Use]
    prefer = Another::Package
    reason = "Please use Another::Package rather than Do::Not::Use"

    [Avoid::Using::This]
    [And::Also::That]

    [No:Reason]
    prefer=A::Better:Module
    
    [Only::Reason]
    reason="If you use this module, a puppy might die."

    [Hard::Ban]
    severity=5
    reason="This module has known security vulnerabilities"

    [Custom::Message]
    message="Do not use Custom::Message - see internal wiki for details"

    [File::Slurper]
    prefer = File::Slurper::Temp
    for = write_binary write_text

Each module entry supports the following optional keys:

=over 4

=item C<prefer> - Suggested replacement module

=item C<reason> - Explanation shown in the violation message

=item C<severity> - Override the policy's default severity for this module (1-5, where 5 is most severe)

=item C<message> - Free-form description that fully replaces the auto-generated violation text

=item C<for> - Restrict the preference to a list of functions (whitespace and/or comma separated)

=back

=head2 Partial preferences

Sometimes the preferred module only implements a part of the API it replaces.
For example L<File::Slurper::Temp> is a rename-in-place writer: it provides the
C<write_> functions of L<File::Slurper> but none of its readers. Recommending it
unconditionally would be wrong.

The C<for> key limits the recommendation to the listed functions:

    [File::Slurper]
    prefer = File::Slurper::Temp
    for = write_binary write_text

With that configuration:

    use File::Slurper qw{ write_text };            # violation
    use File::Slurper qw{ read_text };             # no violation
    use File::Slurper qw{ read_text write_text };  # violation

When the import list does not name any of them - because there is no import
list, or because it only uses export tags - the rest of the document is
inspected instead, and the violation is only reported if one of the listed
functions is actually called, either directly or fully qualified:

    use File::Slurper;
    write_text( $file, $content );                 # violation

    require File::Slurper;
    File::Slurper::read_text($file);               # no violation

=head1 PARENT AND BASE CLASS CHECKING

When the policy encounters C<use parent> or C<use base> statements, it also
checks the modules passed as arguments. For example, if C<Banned::Module> is
in your configuration file, all of these will trigger a violation:

    use Banned::Module;
    use parent 'Banned::Module';
    use base qw(Banned::Module);
    use parent -norequire, 'Banned::Module';

=head1 SEE ALSO

L<Perl::Critic>

=cut
