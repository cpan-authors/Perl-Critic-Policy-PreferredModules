# NAME

Perl::Critic::Policy::PreferredModules - Provide custom package recommendations

# VERSION

version 0.005

# DESCRIPTION

Every project has its own rules for preferring specific packages over others.

This Policy tries to be \`un-opinionated\` and let the user provide a module
preferences with an explanation and/or suggested alternative.

# MODULES

# CONFIGURATION

To use [Perl::Critic::Policy::PreferredModules](https://metacpan.org/pod/Perl%3A%3ACritic%3A%3APolicy%3A%3APreferredModules) you have first to enable it in your
 `.perlcriticrc` file by providing a `preferred_modules.ini` configuration file:

```perl
[PreferredModules]
config = /path/to/preferred_modules.ini
# you can also use '~' in the path for $HOME
#config = ~/.preferred_modules
```

The  `preferred_modules.ini` file is using the [Config::INI](https://metacpan.org/pod/Config%3A%3AINI) format and can looks like this

```perl
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

[perl/rand]
prefer = Crypt::PRNG
```

Each module entry supports the following optional keys:

- `prefer` - Suggested replacement module
- `reason` - Explanation shown in the violation message
- `severity` - Override the policy's default severity for this module (1-5, where 5 is most severe)
- `message` - Free-form description that fully replaces the auto-generated violation text
- `for` - Restrict the preference to a list of functions (whitespace and/or comma separated)

## Partial preferences

Sometimes the preferred module only implements a part of the API it replaces.
For example [File::Slurper::Temp](https://metacpan.org/pod/File%3A%3ASlurper%3A%3ATemp) is a rename-in-place writer: it provides the
`write_` functions of [File::Slurper](https://metacpan.org/pod/File%3A%3ASlurper) but none of its readers. Recommending it
unconditionally would be incorrect.

The `for` key limits the recommendation to the listed functions:

```
[File::Slurper]
prefer = File::Slurper::Temp
for = write_binary write_text
```

With that configuration:

```perl
use File::Slurper qw{ write_text };            # violation
use File::Slurper qw{ read_text };             # no violation
use File::Slurper qw{ read_text write_text };  # violation
```

When the import list does not name any of them - because there is no import
list, or because it only uses export tags - the rest of the document is
inspected instead, and the violation is only reported if one of the listed
functions is actually called, either directly or fully qualified:

```perl
use File::Slurper;
write_text( $file, $content );                 # violation

require File::Slurper;
File::Slurper::read_text($file);               # no violation
```

## Preferring a module's implementation of a builtin function

A section named `[perl/<function>]` applies to calls to the builtin
function rather than to a module import. Use one section per function:

```
[perl/rand]
prefer = Crypt::PRNG
reason = the builtin rand is not cryptographically secure
```

These sections accept the same `prefer`, `reason` and `severity` keys as a
module entry. `for` is not accepted: the function is already named by the
section itself.

A bare `[perl]` section is rejected, since duplicate INI
section names silently collapse into one.

The call has to be a real function call, so method calls, hash keys and
subroutine declarations of the same name are left alone:

```perl
my $x = rand();                # violation
my $x = rand;                  # violation
my $x = $prng->rand;           # no violation
my %h = ( rand => 1 );         # no violation
```

### Calls to the preferred implementation are not reported

When the preferred module is imported in a way that provides the function, a
call to that name _is_ the preferred implementation, so nothing is reported.

```perl
use Crypt::PRNG qw{ rand };
my $x = rand();                # no violation, this is Crypt::PRNG::rand

use Crypt::PRNG ();            # imports nothing
my $x = rand();                # violation, this is the builtin
```

The whole document is considered, not just the enclosing scope.
Use an empty import list, e.g. `use Crypt::PRNG ()` if you want to be fully
sure you never call the builtin.
Fully qualified calls such as `Crypt::PRNG::rand()` never
match a `[perl/rand]` section to begin with, since the section only applies to
unqualified calls.

### A bare `use` is checked against the module's exports

An import list that names the function can be read straight off the source, but
a bare `use Crypt::PRNG` only helps if the module hands the function over by
default. Taking that on trust would hide the very mistake this is meant to
catch, because `Crypt::PRNG` declares `@EXPORT = qw()`:

```perl
use Crypt::PRNG;
my $x = rand();                # violation, this is still the builtin
```

That reads as though the configuration is being honoured while every call goes
to the builtin. The explanation says what happened and how to fix it:

```perl
Crypt::PRNG exports rand on request only, so this call is still the
builtin - import it explicitly with `use Crypt::PRNG qw{ rand }`
```

To answer that question the module named by `prefer` is loaded, unless it is
already in `%INC`, and its `@EXPORT`, `@EXPORT_OK` and `%EXPORT_TAGS` are
read from the symbol table - the same lists [Exporter](https://metacpan.org/pod/Exporter) itself consults, so
exports built at load time or inherited from a parent are accounted for. Only
modules you name in your own configuration are ever loaded, and each is resolved
at most once per run.

### This requires `-allow-unsafe`

Loading a module runs its code: `BEGIN` blocks, top level statements, whatever
the author put there. That is more than static analysis is normally allowed to
do, so a configuration that needs it is treated as unsafe and [Perl::Critic](https://metacpan.org/pod/Perl%3A%3ACritic)
will not load this policy without `-allow-unsafe`:

```
perlcritic --allow-unsafe ...
```

or, in your `.perlcriticrc`:

```
allow_unsafe = 1
```

Only a `[perl/<function>]` section that names a `prefer` module makes
the policy unsafe, because nothing else here loads anything. Module preferences,
`for` lists, and builtin sections without a `prefer` all stay safe and need no
flag.

Note that the policy is silently left out when the flag is missing, which is how
[Perl::Critic](https://metacpan.org/pod/Perl%3A%3ACritic) handles every unsafe policy. If your `[perl/...]` sections seem
to do nothing, that is the first thing to check. `--single-policy` bypasses the
safety check altogether, so it will run these sections without the flag.

If a module will not load in the process running the policy, its source is
located in `@INC` and parsed instead. That fallback only understands literal
declarations, so a list built at runtime is invisible to it.

Export tags are resolved from the same lists:

```perl
use Crypt::PRNG qw{ :all };
my $x = rand();                # no violation, :all covers rand
```

When the exports cannot be resolved at all - the module is not installed, or its
lists are built in a way the fallback cannot read - the function is assumed to
be provided and nothing is reported, so an unresolvable module never turns into
a false positive.

Leaving `prefer` out discourages the builtin outright:

```
[perl/each]
reason = iterating with each() is error prone
severity = 4
```

# PARENT AND BASE CLASS CHECKING

When the policy encounters `use parent` or `use base` statements, it also
checks the modules passed as arguments. For example, if `Banned::Module` is
in your configuration file, all of these will trigger a violation:

```perl
use Banned::Module;
use parent 'Banned::Module';
use base qw(Banned::Module);
use parent -norequire, 'Banned::Module';
```

# CONDITIONAL LOADING

The policy detects modules loaded via `use if`:

```perl
use if $] >= 5.010, 'Some::Module';
```

If `Some::Module` is listed in the configuration file, a violation will be
reported. This ensures that conditional imports are not silently overlooked.

# SEE ALSO

[Perl::Critic](https://metacpan.org/pod/Perl%3A%3ACritic)

# AUTHOR

Nicolas R <nicolas@atoomic.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2026 by WebPros International, LLC.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
