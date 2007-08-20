%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1996-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% File: hlds_data.m.
% Main authors: fjh, conway.
%
% This module defines the part of the HLDS that deals with issues related
% to data and its representation: function symbols, types, insts, modes.
% 
%-----------------------------------------------------------------------------%

:- module hlds.hlds_data.
:- interface.

:- import_module hlds.hlds_pred.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.program_representation.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module multi_map.
:- import_module maybe.
:- import_module pair.
:- import_module set.

:- implementation.

:- import_module check_hlds.type_util.
:- import_module libs.compiler_util.
:- import_module parse_tree.prog_type_subst.

:- import_module int.
:- import_module svmap.
:- import_module svmulti_map.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % The symbol table for constructors. This table is used by the type-checker
    % to look up the type of functors/constants.
    %
:- type cons_table  ==  map(cons_id, list(hlds_cons_defn)).

    % A cons_defn is the definition of a constructor (i.e. a constant
    % or a functor) for a particular type.
    %
:- type hlds_cons_defn
    --->    hlds_cons_defn(
                % maybe add tvarset here?
                % you can get the tvarset from the hlds.type_defn.
                cons_exist_tvars    :: existq_tvars,
                                    % existential type vars

                cons_constraints    :: list(prog_constraint),
                                    % existential class constraints

                cons_args           :: list(constructor_arg),
                                    % The field names and types of the
                                    % arguments of this functor (if any)

                cons_type_ctor      :: type_ctor,
                                    % The result type, i.e. the type to which
                                    % this cons_defn belongs.

                cons_context        :: prog_context
                                    % The location of this constructor
                                    % definition in the original source code.
            ).

%-----------------------------------------------------------------------------%

:- type ctor_field_table == map(ctor_field_name, list(hlds_ctor_field_defn)).

:- type hlds_ctor_field_defn
    --->    hlds_ctor_field_defn(
                field_context   :: prog_context,
                                % context of the field definition

                field_status    :: import_status,

                field_type_ctor :: type_ctor,
                                % type containing the field

                field_cons_id   :: cons_id,
                                % constructor containing the field

                field_arg_num   :: int
                                % argument number (counting from 1)
            ).

    % Field accesses are expanded into inline unifications by post_typecheck.m
    % after typechecking has worked out which field is being referred to.
    %
    % Function declarations and clauses are not generated for these because
    % it would be difficult to work out how to mode them.
    %
    % Users can supply type and mode declarations, for example to export
    % a field of an abstract data type or to allow taking the address
    % of a field access function.
    %
:- type field_access_type
    --->    get
    ;       set.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % The symbol table for types.
    %
:- type type_table  ==  map(type_ctor, hlds_type_defn).

    % This is how type, modes and constructors are represented. The parts that
    % are not defined here (i.e. type_param, constructor, type, inst and mode)
    % are represented in the same way as in prog_io.m, and are defined there.
    %
    % An hlds_type_defn holds the information about a type definition.
:- type hlds_type_defn.

:- pred set_type_defn(tvarset::in, list(type_param)::in,
    tvar_kind_map::in, hlds_type_body::in, import_status::in, bool::in,
    need_qualifier::in, prog_context::in, hlds_type_defn::out) is det.

:- pred get_type_defn_tvarset(hlds_type_defn::in, tvarset::out) is det.
:- pred get_type_defn_tparams(hlds_type_defn::in, list(type_param)::out)
    is det.
:- pred get_type_defn_kind_map(hlds_type_defn::in, tvar_kind_map::out) is det.
:- pred get_type_defn_body(hlds_type_defn::in, hlds_type_body::out) is det.
:- pred get_type_defn_status(hlds_type_defn::in, import_status::out) is det.
:- pred get_type_defn_in_exported_eqv(hlds_type_defn::in, bool::out) is det.
:- pred get_type_defn_need_qualifier(hlds_type_defn::in, need_qualifier::out)
    is det.
:- pred get_type_defn_context(hlds_type_defn::in, prog_context::out) is det.

:- pred set_type_defn_body(hlds_type_body::in,
    hlds_type_defn::in, hlds_type_defn::out) is det.
:- pred set_type_defn_tvarset(tvarset::in,
    hlds_type_defn::in, hlds_type_defn::out) is det.
:- pred set_type_defn_status(import_status::in,
    hlds_type_defn::in, hlds_type_defn::out) is det.
:- pred set_type_defn_in_exported_eqv(bool::in,
    hlds_type_defn::in, hlds_type_defn::out) is det.

    % An `hlds_type_body' holds the body of a type definition:
    % du = discriminated union, eqv_type = equivalence type (a type defined
    % to be equivalent to some other type), and solver_type.
    %
:- type hlds_type_body
    --->    hlds_du_type(
                % The ctors for this type.
                du_type_ctors           :: list(constructor),

                % Their tag values.
                du_type_cons_tag_values :: cons_tag_values,

                % Is this type an enumeration?
                du_type_is_enum         :: enum_or_dummy,

                % User-defined equality and comparison preds.
                du_type_usereq          :: maybe(unify_compare),

                % Is there a `:- pragma reserve_tag' pragma for this type?
                du_type_reserved_tag    :: bool,

                % Are there `:- pragma foreign' type declarations for
                % this type?
                du_type_is_foreign_type :: maybe(foreign_type_body)
            )
    ;       hlds_eqv_type(mer_type)
    ;       hlds_foreign_type(foreign_type_body)
    ;       hlds_solver_type(solver_type_details, maybe(unify_compare))
    ;       hlds_abstract_type(is_solver_type).

:- type enum_or_dummy
    --->    is_enum
    ;       is_dummy
    ;       is_foreign_enum
    ;       not_enum_or_dummy.

:- type foreign_type_body
    --->    foreign_type_body(
                il      :: foreign_type_lang_body(il_foreign_type),
                c       :: foreign_type_lang_body(c_foreign_type),
                java    :: foreign_type_lang_body(java_foreign_type),
                erlang  :: foreign_type_lang_body(erlang_foreign_type)
            ).

:- type foreign_type_lang_body(T) == maybe(foreign_type_lang_data(T)).

    % Foreign types may have user-defined equality and comparison
    % preds, but not solver_type_details.
    %
:- type foreign_type_lang_data(T)
    --->    foreign_type_lang_data(
                T,
                maybe(unify_compare),
                list(foreign_type_assertion)
            ).

    % The `cons_tag_values' type stores the information on how a discriminated
    % union type is represented. For each functor in the d.u. type, it gives
    % a cons_tag which specifies how that functor and its arguments are
    % represented.
    %
:- type cons_tag_values == map(cons_id, cons_tag).

    % A `cons_tag' specifies how a functor and its arguments (if any) are
    % represented. Currently all values are represented as a single word;
    % values which do not fit into a word are represented by a (possibly
    % tagged) pointer to memory on the heap.
    %
:- type cons_tag
    --->    string_tag(string)
            % Strings are represented using the MR_string_const() macro;
            % in the current implementation, Mercury strings are represented
            % just as C null-terminated strings.

    ;       float_tag(float)
            % Floats are represented using the MR_float_to_word(),
            % MR_word_to_float(), and MR_float_const() macros. The default
            % implementation of these is to use boxed double-precision floats.

    ;       int_tag(int)
            % This means the constant is represented just as a word containing
            % the specified integer value. This is used for enumerations and
            % character constants as well as for int constants.
    
    ;       foreign_tag(string)
            % This means the constant is represented by the string which is
            % embedded directly in the target language.  This is used for
            % foreign enumerations, i.e. those enumeration types that are the
            % subject of a foreign_enum pragma.

    ;       pred_closure_tag(pred_id, proc_id, lambda_eval_method)
            % Higher-order pred closures tags. These are represented as
            % a pointer to an argument vector. For closures with
            % lambda_eval_method `normal', the first two words of the argument
            % vector hold the number of args and the address of the procedure
            % respectively. The remaining words hold the arguments.

    ;       type_ctor_info_tag(module_name, string, arity)
            % This is how we refer to type_ctor_info structures represented
            % as global data. The args are the name of the module the type
            % is defined in, and the name of the type, and its arity.

    ;       base_typeclass_info_tag(module_name, class_id, string)
            % This is how we refer to base_typeclass_info structures
            % represented as global data. The first argument is the name
            % of the module containing the instance declaration, the second
            % is the class name and arity, while the third is the string which
            % uniquely identifies the instance declaration (it is made from
            % the type of the arguments to the instance decl).

    ;       tabling_info_tag(pred_id, proc_id)
            % This is how we refer to the global structures containing
            % tabling pointer variables and related data. The word just
            % contains the address of the global struct.

    ;       deep_profiling_proc_layout_tag(pred_id, proc_id)
            % This is for constants representing procedure descriptions for
            % deep profiling.

    ;       table_io_decl_tag(pred_id, proc_id)
            % This is for constants representing the structure that allows us
            % to decode the contents of the memory block containing the
            % headvars of I/O primitives.

    ;       single_functor_tag
            % This is for types with a single functor (and possibly also some
            % constants represented using reserved addresses -- see below).
            % For these types, we don't need any tags. We just store a pointer
            % to the argument vector.

    ;       unshared_tag(tag_bits)
            % This is for constants or functors which can be distinguished
            % with just a primary tag. An "unshared" tag is one which fits
            % on the bottom of a pointer (i.e.  two bits for 32-bit
            % architectures, or three bits for 64-bit architectures), and is
            % used for just one functor. For constants we store a tagged zero,
            % for functors we store a tagged pointer to the argument vector.

    ;       shared_remote_tag(tag_bits, int)
            % This is for functors or constants which require more than just
            % a two-bit tag. In this case, we use both a primary and a
            % secondary tag. Several functors share the primary tag and are
            % distinguished by the secondary tag. The secondary tag is stored
            % as the first word of the argument vector. (If it is a constant,
            % then in this case there is an argument vector of size 1 which
            % just holds the secondary tag.)

    ;       shared_local_tag(tag_bits, int)
            % This is for constants which require more than a two-bit tag.
            % In this case, we use both a primary and a secondary tag,
            % but this time the secondary tag is stored in the rest of the
            % main word rather than in the first word of the argument vector.

    ;       no_tag
            % This is for types with a single functor of arity one. In this
            % case, we don't need to store the functor, and instead we store
            % the argument directly.

    ;       reserved_address_tag(reserved_address)
            % This is for constants represented as null pointers, or as
            % other reserved values in the address space.

    ;       shared_with_reserved_addresses_tag(list(reserved_address),
                cons_tag).
            % This is for constructors of discriminated union types where
            % one or more of the *other* constructors for that type is
            % represented as a reserved address. Any semidet deconstruction
            % against a constructor represented as a
            % shared_with_reserved_addresses cons_tag must check that
            % the value isn't any of the reserved addresses before testing
            % for the constructor's own cons_tag.

:- type reserved_address
    --->    null_pointer
            % This is for constants which are represented as a null pointer.

    ;       small_pointer(int)
            % This is for constants which are represented as a small integer,
            % cast to a pointer.

    ;       reserved_object(type_ctor, sym_name, arity).
            % This is for constants which are represented as the address
            % of a specially reserved global variable.

    % The type `tag_bits' holds a primary tag value.
    %
:- type tag_bits    ==  int.    % actually only 2 (or maybe 3) bits

    % The type definitions for no_tag types have information mirrored in a
    % separate table for faster lookups. mode_util.mode_to_arg_mode makes
    % heavy use of type_util.type_is_no_tag_type.
    %
:- type no_tag_type
    --->    no_tag_type(
                list(type_param),   % Formal type parameters.
                sym_name,           % Constructor name.
                mer_type              % Argument type.
            ).

:- type no_tag_type_table == map(type_ctor, no_tag_type).

    % Return the primary tag, if any, for a cons_tag.
    % A return value of `no' means the primary tag is unknown.
    % A return value of `yes(N)' means the primary tag is N.
    % (`yes(0)' also corresponds to the case where there no primary tag.)
    %
:- func get_primary_tag(cons_tag) = maybe(int).

    % Return the secondary tag, if any, for a cons_tag.
    % A return value of `no' means there is no secondary tag.
    %
:- func get_secondary_tag(cons_tag) = maybe(int).

    % The atomic variants of the Boehm gc allocator calls (e.g.
    % GC_malloc_atomic instead of GC_malloc) may yield slightly faster code
    % since atomic blocks are not scanned for included pointers. However,
    % this makes them safe to use *only* if the block allocated this way
    % can never contain any pointer the Boehm collector would be interested
    % in tracing. In particular, even if the cell initially contains no
    % pointers, we must still use may_not_use_atomic_alloc for it if the cell
    % could possibly be reused later by compile-time garbage collection.
    %
:- type may_use_atomic_alloc
    --->    may_use_atomic_alloc
    ;       may_not_use_atomic_alloc.

:- implementation.

% In some of the cases where we return `no' here,
% it would probably be OK to return `yes(0)'.
% But it's safe to be conservative...
get_primary_tag(string_tag(_)) = no.
get_primary_tag(float_tag(_)) = no.
get_primary_tag(int_tag(_)) = no.
get_primary_tag(foreign_tag(_)) = no.
get_primary_tag(pred_closure_tag(_, _, _)) = no.
get_primary_tag(type_ctor_info_tag(_, _, _)) = no.
get_primary_tag(base_typeclass_info_tag(_, _, _)) = no.
get_primary_tag(tabling_info_tag(_, _)) = no.
get_primary_tag(deep_profiling_proc_layout_tag(_, _)) = no.
get_primary_tag(table_io_decl_tag(_, _)) = no.
get_primary_tag(single_functor_tag) = yes(0).
get_primary_tag(unshared_tag(PrimaryTag)) = yes(PrimaryTag).
get_primary_tag(shared_remote_tag(PrimaryTag, _SecondaryTag))
        = yes(PrimaryTag).
get_primary_tag(shared_local_tag(PrimaryTag, _)) = yes(PrimaryTag).
get_primary_tag(no_tag) = no.
get_primary_tag(reserved_address_tag(_)) = no.
get_primary_tag(shared_with_reserved_addresses_tag(_RAs, TagValue))
        = get_primary_tag(TagValue).

get_secondary_tag(string_tag(_)) = no.
get_secondary_tag(float_tag(_)) = no.
get_secondary_tag(int_tag(_)) = no.
get_secondary_tag(foreign_tag(_)) = no.
get_secondary_tag(pred_closure_tag(_, _, _)) = no.
get_secondary_tag(type_ctor_info_tag(_, _, _)) = no.
get_secondary_tag(base_typeclass_info_tag(_, _, _)) = no.
get_secondary_tag(tabling_info_tag(_, _)) = no.
get_secondary_tag(deep_profiling_proc_layout_tag(_, _)) = no.
get_secondary_tag(table_io_decl_tag(_, _)) = no.
get_secondary_tag(single_functor_tag) = no.
get_secondary_tag(unshared_tag(_)) = no.
get_secondary_tag(shared_remote_tag(_PrimaryTag, SecondaryTag))
        = yes(SecondaryTag).
get_secondary_tag(shared_local_tag(_, _)) = no.
get_secondary_tag(no_tag) = no.
get_secondary_tag(reserved_address_tag(_)) = no.
get_secondary_tag(shared_with_reserved_addresses_tag(_RAs, TagValue))
        = get_secondary_tag(TagValue).

:- type hlds_type_defn
    --->    hlds_type_defn(
                % Names of the type variables, if any.
                type_defn_tvarset           :: tvarset,

                % Formal type parameters.
                type_defn_params            :: list(type_param),

                % Kinds of the formal parameters.
                type_defn_kinds             :: tvar_kind_map,

                % The definition of the type.
                type_defn_body              :: hlds_type_body,

                % Is the type defined in this module, and if yes,
                % is it exported.
                type_defn_import_status     :: import_status,

                % Does the type constructor appear on the right hand side
                % of a type equivalence defining a type that is visible from
                % outside this module? If yes, equiv_type_hlds may generate
                % references to this type constructor's unify and compare preds
                % from other modules even if the type is otherwise local
                % to the module, so we can't make their implementations private
                % to the module.
                %
                % Meaningful only after the equiv_type_hlds pass.
                type_defn_in_exported_eqv   :: bool,

                % Do uses of the type and its constructors need to be
                % qualified.
                type_defn_need_qualifier    :: need_qualifier,

                % The location of this type definition in the original
                % source code.
                type_defn_context           :: prog_context
            ).

set_type_defn(Tvarset, Params, Kinds, Body, Status, InExportedEqv,
        NeedQual, Context, Defn) :-
    Defn = hlds_type_defn(Tvarset, Params, Kinds, Body, Status,
        InExportedEqv, NeedQual, Context).

get_type_defn_tvarset(Defn, Defn ^ type_defn_tvarset).
get_type_defn_tparams(Defn, Defn ^ type_defn_params).
get_type_defn_kind_map(Defn, Defn ^ type_defn_kinds).
get_type_defn_body(Defn, Defn ^ type_defn_body).
get_type_defn_status(Defn, Defn ^ type_defn_import_status).
get_type_defn_in_exported_eqv(Defn, Defn ^ type_defn_in_exported_eqv).
get_type_defn_need_qualifier(Defn, Defn ^ type_defn_need_qualifier).
get_type_defn_context(Defn, Defn ^ type_defn_context).

set_type_defn_body(Body, Defn, Defn ^ type_defn_body := Body).
set_type_defn_tvarset(TVarSet, Defn,
        Defn ^ type_defn_tvarset := TVarSet).
set_type_defn_status(Status, Defn,
        Defn ^ type_defn_import_status := Status).
set_type_defn_in_exported_eqv(InExportedEqv, Defn,
        Defn ^ type_defn_in_exported_eqv := InExportedEqv).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % The symbol table for insts.
    %
:- type inst_table.

:- type user_inst_table.
:- type user_inst_defns ==  map(inst_id, hlds_inst_defn).

:- type unify_inst_table == map(inst_name, maybe_inst_det).

:- type unify_inst_pair
    --->    unify_inst_pair(
                is_live,
                mer_inst,
                mer_inst,
                unify_is_real
            ).

:- type merge_inst_table == map(pair(mer_inst), maybe_inst).

:- type ground_inst_table ==    map(inst_name, maybe_inst_det).

:- type any_inst_table ==   map(inst_name, maybe_inst_det).

:- type shared_inst_table ==    map(inst_name, maybe_inst).

:- type mostly_uniq_inst_table == map(inst_name, maybe_inst).

:- type maybe_inst
    --->    inst_unknown
    ;       inst_known(mer_inst).

:- type maybe_inst_det
    --->    inst_det_unknown
    ;       inst_det_known(mer_inst, determinism).

    % An `hlds_inst_defn' holds the information we need to store
    % about inst definitions such as
    %   :- inst list_skel(I) = bound([] ; [I | list_skel(I)].
    %
:- type hlds_inst_defn
    --->    hlds_inst_defn(
                inst_varset     :: inst_varset,
                                % The names of the inst parameters (if any).

                inst_params     :: list(inst_var),
                                % The inst parameters (if any).
                                % ([I] in the above example.)

                inst_body       :: hlds_inst_body,
                                % The definition of this inst.

                inst_context    :: prog_context,
                                % The location in the source code of this inst
                                % definition.

                inst_status     :: import_status
                                % So intermod.m can tell whether to output
                                % this inst.
            ).

:- type hlds_inst_body
    --->    eqv_inst(mer_inst)  % This inst is equivalent to
                                % some other inst.

    ;       abstract_inst.      % This inst is just a forward declaration;
                                % the real definition will be filled in later.
                                % (XXX Abstract insts are not really
                                % supported.)

%-----------------------------------------------------------------------------%

:- pred inst_table_init(inst_table::out) is det.

:- pred inst_table_get_user_insts(inst_table::in, user_inst_table::out) is det.
:- pred inst_table_get_unify_insts(inst_table::in, unify_inst_table::out)
    is det.
:- pred inst_table_get_merge_insts(inst_table::in, merge_inst_table::out)
    is det.
:- pred inst_table_get_ground_insts(inst_table::in, ground_inst_table::out)
    is det.
:- pred inst_table_get_any_insts(inst_table::in, any_inst_table::out) is det.
:- pred inst_table_get_shared_insts(inst_table::in, shared_inst_table::out)
    is det.
:- pred inst_table_get_mostly_uniq_insts(inst_table::in,
    mostly_uniq_inst_table::out) is det.

:- pred inst_table_set_user_insts(user_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_unify_insts(unify_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_merge_insts(merge_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_ground_insts(ground_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_any_insts(any_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_shared_insts(shared_inst_table::in,
    inst_table::in, inst_table::out) is det.
:- pred inst_table_set_mostly_uniq_insts(mostly_uniq_inst_table::in,
    inst_table::in, inst_table::out) is det.

:- pred user_inst_table_get_inst_defns(user_inst_table::in,
    user_inst_defns::out) is det.
:- pred user_inst_table_get_inst_ids(user_inst_table::in,
    list(inst_id)::out) is det.

:- pred user_inst_table_insert(inst_id::in, hlds_inst_defn::in,
    user_inst_table::in, user_inst_table::out) is semidet.

    % Optimize the user_inst_table for lookups. This just sorts
    % the cached list of inst_ids.
:- pred user_inst_table_optimize(user_inst_table::in, user_inst_table::out)
    is det.

:- implementation.

:- type inst_table
    --->    inst_table(
                inst_table_user         :: user_inst_table,
                inst_table_unify        :: unify_inst_table,
                inst_table_merge        :: merge_inst_table,
                inst_table_ground       :: ground_inst_table,
                inst_table_any          :: any_inst_table,
                inst_table_shared       :: shared_inst_table,
                inst_table_mostly_uniq  :: mostly_uniq_inst_table
            ).

:- type user_inst_defns.

:- type user_inst_table
    --->    user_inst_table(
                uinst_table_defns   :: user_inst_defns,
                uinst_table_ids     :: list(inst_id)
                                    % Cached for efficiency when module
                                    % qualifying the modes of lambda
                                    % expressions.
            ).

inst_table_init(inst_table(UserInsts, UnifyInsts, MergeInsts, GroundInsts,
            AnyInsts, SharedInsts, NondetLiveInsts)) :-
    map.init(UserInstDefns),
    UserInsts = user_inst_table(UserInstDefns, []),
    map.init(UnifyInsts),
    map.init(MergeInsts),
    map.init(GroundInsts),
    map.init(SharedInsts),
    map.init(AnyInsts),
    map.init(NondetLiveInsts).

inst_table_get_user_insts(InstTable, InstTable ^ inst_table_user).
inst_table_get_unify_insts(InstTable, InstTable ^ inst_table_unify).
inst_table_get_merge_insts(InstTable, InstTable ^ inst_table_merge).
inst_table_get_ground_insts(InstTable, InstTable ^ inst_table_ground).
inst_table_get_any_insts(InstTable, InstTable ^ inst_table_any).
inst_table_get_shared_insts(InstTable, InstTable ^ inst_table_shared).
inst_table_get_mostly_uniq_insts(InstTable,
    InstTable ^ inst_table_mostly_uniq).

inst_table_set_user_insts(UserInsts, InstTable,
    InstTable ^ inst_table_user := UserInsts).
inst_table_set_unify_insts(UnifyInsts, InstTable,
    InstTable ^ inst_table_unify := UnifyInsts).
inst_table_set_merge_insts(MergeInsts, InstTable,
    InstTable ^ inst_table_merge := MergeInsts).
inst_table_set_ground_insts(GroundInsts, InstTable,
    InstTable ^ inst_table_ground := GroundInsts).
inst_table_set_any_insts(AnyInsts, InstTable,
    InstTable ^ inst_table_any := AnyInsts).
inst_table_set_shared_insts(SharedInsts, InstTable,
    InstTable ^ inst_table_shared := SharedInsts).
inst_table_set_mostly_uniq_insts(MostlyUniqInsts, InstTable,
    InstTable ^ inst_table_mostly_uniq := MostlyUniqInsts).

user_inst_table_get_inst_defns(UserInstTable,
    UserInstTable ^ uinst_table_defns).
user_inst_table_get_inst_ids(UserInstTable,
    UserInstTable ^ uinst_table_ids).

user_inst_table_insert(InstId, InstDefn, UserInstTable0, UserInstTable) :-
    UserInstTable0 = user_inst_table(InstDefns0, InstIds0),
    InstDefns0 = UserInstTable0 ^ uinst_table_defns,
    map.insert(InstDefns0, InstId, InstDefn, InstDefns),
    InstIds = [InstId | InstIds0],
    UserInstTable = user_inst_table(InstDefns, InstIds).

user_inst_table_optimize(UserInstTable0, UserInstTable) :-
    UserInstTable0 = user_inst_table(InstDefns0, InstIds0),
    map.optimize(InstDefns0, InstDefns),
    list.sort(InstIds0, InstIds),
    UserInstTable = user_inst_table(InstDefns, InstIds).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % The symbol table for modes.
    %
:- type mode_table.
:- type mode_defns   == map(mode_id, hlds_mode_defn).

    % A hlds_mode_defn stores the information about a mode
    % definition such as
    %   :- mode out == free >> ground.
    % or
    %   :- mode in(I) == I >> I.
    % or
    %   :- mode in_list_skel == in(list_skel).
    %
:- type hlds_mode_defn
    --->    hlds_mode_defn(
                mode_varset     :: inst_varset,
                                % The names of the inst parameters (if any).

                mode_params     :: list(inst_var),
                                % The list of the inst parameters (if any).
                                % (e.g. [I] for the second example above.)

                mody_body       :: hlds_mode_body,
                                % The definition of this mode.

                mode_context    :: prog_context,
                                % The location of this mode definition in the
                                % original source code.

                mode_status     :: import_status
                                % So intermod.m can tell whether to output
                                % this mode.
            ).

    % The only sort of mode definitions allowed are equivalence modes.
    %
:- type hlds_mode_body
    --->    eqv_mode(mer_mode).  % This mode is equivalent to some other mode.

    % Given a mode table get the mode_id - hlds_mode_defn map.
    %
:- pred mode_table_get_mode_defns(mode_table::in, mode_defns::out) is det.

    % Get the list of defined mode_ids from the mode_table.
    %
:- pred mode_table_get_mode_ids(mode_table::in, list(mode_id)::out) is det.

    % Insert a mode_id and corresponding hlds_mode_defn into the mode_table.
    % Fail if the mode_id is already present in the table.
    %
:- pred mode_table_insert(mode_id::in, hlds_mode_defn::in,
    mode_table::in, mode_table::out) is semidet.

:- pred mode_table_init(mode_table::out) is det.

    % Optimize the mode table for lookups.
    %
:- pred mode_table_optimize(mode_table::in, mode_table::out) is det.

:- implementation.

:- type mode_table
    --->    mode_table(
                mode_table_defns    :: mode_defns,
                mode_table_ids      :: list(mode_id)
                                    % Cached for efficiency
            ).

mode_table_get_mode_defns(ModeTable, ModeTable ^ mode_table_defns).
mode_table_get_mode_ids(ModeTable, ModeTable ^ mode_table_ids).

mode_table_insert(ModeId, ModeDefn, ModeTable0, ModeTable) :-
    ModeTable0 = mode_table(ModeDefns0, ModeIds0),
    map.insert(ModeDefns0, ModeId, ModeDefn, ModeDefns),
    ModeIds = [ModeId | ModeIds0],
    ModeTable = mode_table(ModeDefns, ModeIds).

mode_table_init(mode_table(ModeDefns, [])) :-
    map.init(ModeDefns).

mode_table_optimize(ModeTable0, ModeTable) :-
    ModeTable0 = mode_table(ModeDefns0, ModeIds0),
    map.optimize(ModeDefns0, ModeDefns),   % NOP
    % Sort the list of mode_ids for quick conversion to a set by module_qual
    % when qualifying the modes of lambda expressions.
    list.sort(ModeIds0, ModeIds),
    ModeTable = mode_table(ModeDefns, ModeIds).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

:- type class_table == map(class_id, hlds_class_defn).

    % Information about a single `typeclass' declaration.
    %
:- type hlds_class_defn
    --->    hlds_class_defn(
                class_status            :: import_status,
                class_supers            :: list(prog_constraint),
                                        % SuperClasses
                class_fundeps           :: hlds_class_fundeps,
                                        % Functional dependencies
                class_fundep_ancestors  :: list(prog_constraint),
                                        % All ancestors which have fundeps
                                        % on them.
                class_vars              :: list(tvar),
                                        % ClassVars
                class_kinds             :: tvar_kind_map,
                                        % Kinds of class_vars.
                class_interface         :: class_interface,
                                        % The interface from the original
                                        % declaration, used by intermod.m to
                                        % write out the interface for a local
                                        % typeclass to the `.opt' file.
                class_hlds_interface    :: hlds_class_interface,
                                        % Methods
                class_tvarset           :: tvarset,
                                        % VarNames
                class_context           :: prog_context
                                        % Location of declaration
            ).

    % In the HLDS, functional dependencies are represented using
    % argument positions (counting from 1) rather than type variables.
    % We know that there will be a one-one correspondence since
    % typeclass parameters must be distinct variables, and using
    % argument positions is more efficient.
    %
:- type hlds_class_fundeps == list(hlds_class_fundep).
:- type hlds_class_fundep
    --->    fundep(
                domain      :: set(hlds_class_argpos),
                range       :: set(hlds_class_argpos)
            ).

:- type hlds_class_argpos == int.

:- func restrict_list_elements(set(hlds_class_argpos), list(T)) = list(T).

:- type hlds_class_interface    ==  list(hlds_class_proc).
:- type hlds_class_proc
    --->    hlds_class_proc(
                pred_id,
                proc_id
            ).

    % For each class, we keep track of a list of its instances, since there
    % can be more than one instance of each class.  Each visible instance
    % is assigned a unique identifier (integers beginning from one).
    % The position in the list of instances corresponds to the instance_id.
    %
:- type instance_table == map(class_id, list(hlds_instance_defn)).

:- type instance_id == int.

    % Information about a single `instance' declaration
    %
:- type hlds_instance_defn
    --->    hlds_instance_defn(
                instance_module         :: module_name,
                                        % module of the instance decl
                instance_status         :: import_status,
                                        % import status of the instance
                                        % declaration
                instance_context        :: prog_context,
                                        % context of declaration
                instance_constraints    :: list(prog_constraint),
                                        % Constraints on the instance
                                        % declaration.
                instance_types          :: list(mer_type),
                                        % ClassTypes
                instance_body           :: instance_body,
                                        % Methods
                instance_hlds_interface :: maybe(hlds_class_interface),
                                        % After check_typeclass, we will know
                                        % the pred_ids and proc_ids of all
                                        % the methods.
                instance_tvarset        :: tvarset,
                                        % VarNames
                instance_proofs         :: constraint_proof_map
                                        % "Proofs" of how to build the
                                        % typeclass_infos for the superclasses
                                        % of this class (that is, the
                                        % constraints on the class
                                        % declaration), for this instance.
            ).

%-----------------------------------------------------------------------------%

:- implementation.

restrict_list_elements(Elements, List) =
    restrict_list_elements_2(Elements, 1, List).

:- func restrict_list_elements_2(set(hlds_class_argpos), hlds_class_argpos,
    list(T)) = list(T).

restrict_list_elements_2(_, _, []) = [].
restrict_list_elements_2(Elements, Index, [X | Xs]) =
    ( set.member(Index, Elements) ->
        [X | restrict_list_elements_2(Elements, Index + 1, Xs)]
    ;
        restrict_list_elements_2(Elements, Index + 1, Xs)
    ).

%-----------------------------------------------------------------------------%

:- interface.

    % Identifiers for constraints which are unique across a given type_assign.
    % Integers in these values refer to the position in the list of constraints
    % at that location, beginning from 1.
    %
    % Only identifiers for constraints appearing directly on a goal are needed
    % at the moment, so there is no way to represent the appropriate identifier
    % for the superclass of such a constraint.
    %
    % XXX A more robust and efficient solution would be to allocate
    % unique integers to the constraints as they are encountered, and
    % store the allocated integer in the relevant hlds_goal_expr.
    %
:- type constraint_id
    --->    constraint_id(
                constraint_type,
                    % Assumed or unproven.

                goal_path,
                    % The location of the atomic goal which is constrained.

                int % The position of the constraint.
            ).

:- type constraint_type
    --->    unproven
    ;       assumed.

    % The identifier of a constraint is stored along with the constraint.
    % Each value of this type may have more than one identifier because
    % if two constraints in a context are equivalent then we merge them
    % together in order to not have to prove the same constraint twice.
    %
:- type hlds_constraint
    --->    constraint(
                list(constraint_id),
                class_name,
                list(mer_type)
            ).

:- type hlds_constraints
    --->    constraints(
                unproven    :: list(hlds_constraint),
                            % Unproven constraints. These are the constraints
                            % that we must prove (that is, universal
                            % constraints from the goal being checked, or
                            % existential constraints on the head).

                assumed     :: list(hlds_constraint),
                            % Assumed constraints. These are constraints
                            % we can use in proofs (that is, existential
                            % constraints from the goal being checked, or
                            % universal constraints on the head).

                redundant   :: redundant_constraints,
                            % Constraints that are known to be redundant.
                            % This includes constraints that have already been
                            % proved as well as constraints that are ancestors
                            % of other unproven, assumed or redundant
                            % constraints.  Not all such constraints are
                            % included, only those which may be used for
                            % the purposes of improvement.

                ancestors   :: ancestor_constraints
                            % Ancestors of assumed constraints.
            ).

    % Redundant constraints are partitioned by class, which helps us
    % process them more efficiently.
    %
:- type redundant_constraints == multi_map(class_id, hlds_constraint).

    % Constraints which are ancestors of assumed constraints, along with the
    % list of constraints (following the class hierarchy) which leads to
    % the assumed constraint.  The assumed constraint is the last item in the
    % list.
    %
    % Note that if there are two possible lists for the same constraint, we
    % always keep the shorter one.
    %
:- type ancestor_constraints == map(prog_constraint, list(prog_constraint)).
 
    % During type checking we fill in a constraint_map which gives
    % the constraint that corresponds to each identifier.  This is used
    % by the polymorphism translation to retrieve details of constraints.
    %
:- type constraint_map == map(constraint_id, prog_constraint).

    % `Proof' of why a constraint is redundant.
:- type constraint_proof
    --->    apply_instance(instance_id)
            % Apply the instance decl with the given identifier. Note that
            % we don't store the actual hlds_instance_defn for two reasons:
            %
            % - That would require storing a renamed version of the
            %   constraint_proofs for *every* use of an instance declaration.
            %   This wouldn't even get GCed for a long time because it
            %   would be stored in the pred_info.
            %
            % - The superclass proofs stored in the hlds_instance_defn would
            %   need to store all the constraint_proofs for all its ancestors.
            %   This would require the class relation to be topologically
            %   sorted before checking the instance declarations.

    ;       superclass(prog_constraint).
            % The constraint is redundant because of the following class's
            % superclass declaration.

    % The constraint_proof_map is a map which for each type class constraint
    % records how/why that constraint was satisfied. This information is used
    % to determine how to construct the typeclass_info for that constraint.
    %
:- type constraint_proof_map == map(prog_constraint, constraint_proof).

:- pred empty_hlds_constraints(hlds_constraints::out) is det.

:- pred init_hlds_constraint_list(list(prog_constraint)::in,
    list(hlds_constraint)::out) is det.

:- pred make_head_hlds_constraints(class_table::in, tvarset::in,
    prog_constraints::in, hlds_constraints::out) is det.

:- pred make_body_hlds_constraints(class_table::in, tvarset::in, goal_path::in,
    prog_constraints::in, hlds_constraints::out) is det.

    % make_hlds_constraints(ClassTable, TVarSet, UnprovenConstraints,
    %   AssumedConstraints, Constraints):
    %
    % ClassTable is the class_table for the module. TVarSet is the tvarset
    % for the predicate this class context is for. UnprovenConstraints is
    % a list of constraints which will need to be proven (that is, universal
    % constraints in the body or existential constraints in the head).
    % AssumedConstraints is a list of constraints that may be used in proofs
    % (that is, existential constraints in the body or universal constraints
    % in the head).
    %
:- pred make_hlds_constraints(class_table::in, tvarset::in,
    list(hlds_constraint)::in, list(hlds_constraint)::in,
    hlds_constraints::out) is det.

:- pred make_hlds_constraint_list(list(prog_constraint)::in,
    constraint_type::in, goal_path::in, list(hlds_constraint)::out) is det.

:- pred merge_hlds_constraints(hlds_constraints::in, hlds_constraints::in,
    hlds_constraints::out) is det.

:- pred retrieve_prog_constraints(hlds_constraints::in, prog_constraints::out)
    is det.

:- pred retrieve_prog_constraint_list(list(hlds_constraint)::in,
    list(prog_constraint)::out) is det.

:- pred retrieve_prog_constraint(hlds_constraint::in, prog_constraint::out)
    is det.

:- pred matching_constraints(hlds_constraint::in, hlds_constraint::in)
    is semidet.

:- pred compare_hlds_constraints(hlds_constraint::in, hlds_constraint::in,
    comparison_result::out) is det.

:- pred update_constraint_map(hlds_constraint::in, constraint_map::in,
    constraint_map::out) is det.

:- pred update_redundant_constraints(class_table::in, tvarset::in,
    list(hlds_constraint)::in,
    redundant_constraints::in, redundant_constraints::out) is det.

:- pred lookup_hlds_constraint_list(constraint_map::in, constraint_type::in,
    goal_path::in, int::in, list(prog_constraint)::out) is det.

:- pred search_hlds_constraint_list(constraint_map::in, constraint_type::in,
    goal_path::in, int::in, list(prog_constraint)::out) is semidet.

%-----------------------------------------------------------------------------%

:- implementation.

empty_hlds_constraints(Constraints) :-
    Constraints = constraints([], [], multi_map.init, map.init).

init_hlds_constraint_list(ProgConstraints, Constraints) :-
    list.map(init_hlds_constraint, ProgConstraints, Constraints).

:- pred init_hlds_constraint(prog_constraint::in, hlds_constraint::out) is det.

init_hlds_constraint(constraint(Name, Types), constraint([], Name, Types)).

make_head_hlds_constraints(ClassTable, TVarSet, ProgConstraints,
        Constraints) :-
    ProgConstraints = constraints(UnivConstraints, ExistConstraints),
    GoalPath = [],
    make_hlds_constraint_list(UnivConstraints, assumed, GoalPath,
        AssumedConstraints),
    make_hlds_constraint_list(ExistConstraints, unproven, GoalPath,
        UnprovenConstraints),
    make_hlds_constraints(ClassTable, TVarSet, UnprovenConstraints,
        AssumedConstraints, Constraints).

make_body_hlds_constraints(ClassTable, TVarSet, GoalPath, ProgConstraints,
        Constraints) :-
    ProgConstraints = constraints(UnivConstraints, ExistConstraints),
    make_hlds_constraint_list(UnivConstraints, unproven, GoalPath,
        UnprovenConstraints),
    make_hlds_constraint_list(ExistConstraints, assumed, GoalPath,
        AssumedConstraints),
    make_hlds_constraints(ClassTable, TVarSet, UnprovenConstraints,
        AssumedConstraints, Constraints).

make_hlds_constraints(ClassTable, TVarSet, Unproven, Assumed, Constraints) :-
    list.foldl(update_redundant_constraints_2(ClassTable, TVarSet),
        Unproven, multi_map.init, Redundant0),
    list.foldl(update_redundant_constraints_2(ClassTable, TVarSet),
        Assumed, Redundant0, Redundant),
    list.foldl(update_ancestor_constraints(ClassTable, TVarSet),
        Assumed, map.init, Ancestors),
    Constraints = constraints(Unproven, Assumed, Redundant, Ancestors).

make_hlds_constraint_list(ProgConstraints, ConstraintType, GoalPath,
        Constraints) :-
    make_hlds_constraint_list_2(ProgConstraints, ConstraintType, GoalPath,
        1, Constraints).

:- pred make_hlds_constraint_list_2(list(prog_constraint)::in,
    constraint_type::in, goal_path::in, int::in,
    list(hlds_constraint)::out) is det.

make_hlds_constraint_list_2([], _, _, _, []).
make_hlds_constraint_list_2([ProgConstraint | ProgConstraints], ConstraintType,
        GoalPath, N, [HLDSConstraint | HLDSConstraints]) :-
    ProgConstraint = constraint(Name, Types),
    Id = constraint_id(ConstraintType, GoalPath, N),
    HLDSConstraint = constraint([Id], Name, Types),
    make_hlds_constraint_list_2(ProgConstraints, ConstraintType, GoalPath,
        N + 1, HLDSConstraints).

merge_hlds_constraints(ConstraintsA, ConstraintsB, Constraints) :-
    ConstraintsA = constraints(UnprovenA, AssumedA, RedundantA, AncestorsA),
    ConstraintsB = constraints(UnprovenB, AssumedB, RedundantB, AncestorsB),
    list.append(UnprovenA, UnprovenB, Unproven),
    list.append(AssumedA, AssumedB, Assumed),
    multi_map.merge(RedundantA, RedundantB, Redundant),
    map.union(shortest_list, AncestorsA, AncestorsB, Ancestors),
    Constraints = constraints(Unproven, Assumed, Redundant, Ancestors).

:- pred shortest_list(list(T)::in, list(T)::in, list(T)::out) is det.

shortest_list(As, Bs, Cs) :-
    ( is_shorter(As, Bs) ->
        Cs = As
    ;
        Cs = Bs
    ).

:- pred is_shorter(list(T)::in, list(T)::in) is semidet.

is_shorter([], _).
is_shorter([_ | As], [_ | Bs]) :-
    is_shorter(As, Bs).

retrieve_prog_constraints(Constraints, ProgConstraints) :-
    Constraints = constraints(Unproven, Assumed, _, _),
    retrieve_prog_constraint_list(Unproven, UnivProgConstraints),
    retrieve_prog_constraint_list(Assumed, ExistProgConstraints),
    ProgConstraints = constraints(UnivProgConstraints, ExistProgConstraints).

retrieve_prog_constraint_list(Constraints, ProgConstraints) :-
    list.map(retrieve_prog_constraint, Constraints, ProgConstraints).

retrieve_prog_constraint(Constraint, ProgConstraint) :-
    Constraint = constraint(_, Name, Types),
    ProgConstraint = constraint(Name, Types).

matching_constraints(constraint(_, Name, Types), constraint(_, Name, Types)).

compare_hlds_constraints(constraint(_, NA, TA), constraint(_, NB, TB), R) :-
    compare(R0, NA, NB),
    ( R0 = (=) ->
        compare(R, TA, TB)
    ;
        R = R0
    ).

update_constraint_map(Constraint, !ConstraintMap) :-
    Constraint = constraint(Ids, Name, Types),
    ProgConstraint = constraint(Name, Types),
    list.foldl(update_constraint_map_2(ProgConstraint), Ids, !ConstraintMap).

:- pred update_constraint_map_2(prog_constraint::in, constraint_id::in,
    constraint_map::in, constraint_map::out) is det.

update_constraint_map_2(ProgConstraint, ConstraintId, ConstraintMap0,
        ConstraintMap) :-
    map.set(ConstraintMap0, ConstraintId, ProgConstraint, ConstraintMap).

update_redundant_constraints(ClassTable, TVarSet, Constraints, !Redundant) :-
    list.foldl(update_redundant_constraints_2(ClassTable, TVarSet),
        Constraints, !Redundant).

:- pred update_redundant_constraints_2(class_table::in, tvarset::in,
    hlds_constraint::in, redundant_constraints::in,
    redundant_constraints::out) is det.

update_redundant_constraints_2(ClassTable, TVarSet, Constraint, !Redundant) :-
    Constraint = constraint(_, Name, Args),
    list.length(Args, Arity),
    ClassId = class_id(Name, Arity),
    map.lookup(ClassTable, ClassId, ClassDefn),
    ClassAncestors0 = ClassDefn ^ class_fundep_ancestors,
    list.map(init_hlds_constraint, ClassAncestors0, ClassAncestors),
    (
        % Optimize the simple case.
        ClassAncestors = []
    ;
        ClassAncestors = [_ | _],
        ClassTVarSet = ClassDefn ^ class_tvarset,
        ClassParams = ClassDefn ^ class_vars,

        % We can ignore the resulting tvarset, since any new variables
        % will become bound when the arguments are bound. (This follows
        % from the fact that constraints on class declarations can only use
        % variables that appear in the head of the declaration.)

        tvarset_merge_renaming(TVarSet, ClassTVarSet, _, Renaming),
        apply_variable_renaming_to_constraint_list(Renaming,
            ClassAncestors, RenamedAncestors),
        apply_variable_renaming_to_tvar_list(Renaming, ClassParams,
            RenamedParams),
        map.from_corresponding_lists(RenamedParams, Args, Subst),
        apply_subst_to_constraint_list(Subst, RenamedAncestors, Ancestors),
        list.foldl(add_redundant_constraint, Ancestors, !Redundant)
    ).

:- pred add_redundant_constraint(hlds_constraint::in,
    redundant_constraints::in, redundant_constraints::out) is det.

add_redundant_constraint(Constraint, !Redundant) :-
    Constraint = constraint(_, Name, Args),
    list.length(Args, Arity),
    ClassId = class_id(Name, Arity),
    svmulti_map.add(ClassId, Constraint, !Redundant).

lookup_hlds_constraint_list(ConstraintMap, ConstraintType, GoalPath, Count,
        Constraints) :-
    (
        search_hlds_constraint_list_2(ConstraintMap, ConstraintType, GoalPath,
            Count, [], Constraints0)
    ->
        Constraints = Constraints0
    ;
        unexpected(this_file, "lookup_hlds_constraint_list: not found")
    ).

search_hlds_constraint_list(ConstraintMap, ConstraintType, GoalPath, Count,
        Constraints) :-
    search_hlds_constraint_list_2(ConstraintMap, ConstraintType, GoalPath,
        Count, [], Constraints).

:- pred search_hlds_constraint_list_2(constraint_map::in, constraint_type::in,
    goal_path::in, int::in, list(prog_constraint)::in,
    list(prog_constraint)::out) is semidet.

search_hlds_constraint_list_2(ConstraintMap, ConstraintType, GoalPath, Count,
        !Constraints) :-
    ( Count = 0 ->
        true
    ;
        ConstraintId = constraint_id(ConstraintType, GoalPath, Count),
        map.search(ConstraintMap, ConstraintId, Constraint),
        !:Constraints = [Constraint | !.Constraints],
        search_hlds_constraint_list_2(ConstraintMap, ConstraintType,
            GoalPath, Count - 1, !Constraints)
    ).

%-----------------------------------------------------------------------------%

    % Search the superclasses of the given constraint for a potential proof,
    % and add it to the map if no better proof exists already.
    %
:- pred update_ancestor_constraints(class_table::in, tvarset::in,
    hlds_constraint::in, ancestor_constraints::in, ancestor_constraints::out)
    is det.

update_ancestor_constraints(ClassTable, TVarSet, HLDSConstraint, !Ancestors) :-
    retrieve_prog_constraint(HLDSConstraint, Constraint),
    update_ancestor_constraints_2(ClassTable, TVarSet, [], Constraint,
        !Ancestors).

:- pred update_ancestor_constraints_2(class_table::in, tvarset::in,
    list(prog_constraint)::in, prog_constraint::in,
    ancestor_constraints::in, ancestor_constraints::out) is det.

update_ancestor_constraints_2(ClassTable, TVarSet, Descendants0, Constraint,
        !Ancestors) :-
    Constraint = constraint(Class, Args),
    list.length(Args, Arity),
    ClassId = class_id(Class, Arity),
    map.lookup(ClassTable, ClassId, ClassDefn),

    % We can ignore the resulting tvarset, since any new variables
    % will become bound when the arguments are bound. (This follows
    % from the fact that constraints on class declarations can only use
    % variables that appear in the head of the declaration.)

    tvarset_merge_renaming(TVarSet, ClassDefn ^ class_tvarset, _, Renaming),
    apply_variable_renaming_to_prog_constraint_list(Renaming,
        ClassDefn ^ class_supers, RenamedSupers),
    apply_variable_renaming_to_tvar_list(Renaming, ClassDefn ^ class_vars,
        RenamedParams),
    map.from_corresponding_lists(RenamedParams, Args, Subst),
    apply_subst_to_prog_constraint_list(Subst, RenamedSupers, Supers),

    Descendants = [Constraint | Descendants0],
    list.foldl(update_ancestor_constraints_3(ClassTable, TVarSet, Descendants),
        Supers, !Ancestors).

:- pred update_ancestor_constraints_3(class_table::in, tvarset::in,
    list(prog_constraint)::in, prog_constraint::in,
    ancestor_constraints::in, ancestor_constraints::out) is det.

update_ancestor_constraints_3(ClassTable, TVarSet, Descendants, Constraint,
        !Ancestors) :-
    (
        map.search(!.Ancestors, Constraint, OldDescendants),
        is_shorter(OldDescendants, Descendants)
    ->
        % We don't want to update the ancestors because we already have a
        % better path.  The same will apply for all superclasses, so we
        % don't traverse any further.
        true
    ;
        svmap.set(Constraint, Descendants, !Ancestors),
        update_ancestor_constraints_2(ClassTable, TVarSet, Descendants,
            Constraint, !Ancestors)
    ).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % A table that records all the assertions in the system.
    % An assertion is a goal that will always evaluate to true,
    % subject to the constraints imposed by the quantifiers.
    %
    % ie :- promise all [A] some [B] (B > A)
    %
    % The above assertion states that for all possible values of A,
    % there will exist at least one value, B, such that B is greater than A.
    %
:- type assert_id.
:- type assertion_table.

:- pred assertion_table_init(assertion_table::out) is det.

:- pred assertion_table_add_assertion(pred_id::in, assert_id::out,
    assertion_table::in, assertion_table::out) is det.

:- pred assertion_table_lookup(assertion_table::in, assert_id::in,
    pred_id::out) is det.

:- pred assertion_table_pred_ids(assertion_table::in,
    list(pred_id)::out) is det.

:- implementation.

:- type assert_id == int.
:- type assertion_table
    --->    assertion_table(assert_id, map(assert_id, pred_id)).

assertion_table_init(assertion_table(0, AssertionMap)) :-
    map.init(AssertionMap).

assertion_table_add_assertion(Assertion, Id, !AssertionTable) :-
    !.AssertionTable = assertion_table(Id, AssertionMap0),
    map.det_insert(AssertionMap0, Id, Assertion, AssertionMap),
    !:AssertionTable = assertion_table(Id + 1, AssertionMap).

assertion_table_lookup(AssertionTable, Id, Assertion) :-
    AssertionTable = assertion_table(_MaxId, AssertionMap),
    map.lookup(AssertionMap, Id, Assertion).

assertion_table_pred_ids(assertion_table(_, AssertionMap), PredIds) :-
    map.values(AssertionMap, PredIds).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- interface.

    % A table recording exclusivity declarations (i.e. promise_exclusive
    % and promise_exclusive_exhaustive).
    %
    % e.g. :- all [X]
    %       promise_exclusive
    %       some [Y] (
    %           p(X, Y)
    %       ;
    %           q(X)
    %       ).
    %
    % promises that only one of p(X, Y) and q(X) can succeed at a time,
    % although whichever one succeeds may have multiple solutions. See
    % notes/promise_ex.html for details of the declarations.

    % An exclusive_id is the pred_id of an exclusivity declaration,
    % and is useful in distinguishing between the arguments of the
    % operations below on the exclusive_table.
    %
:- type exclusive_id    ==  pred_id.
:- type exclusive_ids   ==  list(pred_id).

:- type exclusive_table.

    % Initialise the exclusive_table.
    %
:- pred exclusive_table_init(exclusive_table::out) is det.

    % Search the exclusive table and return the list of exclusivity
    % declarations that use the predicate given by pred_id.
    %
:- pred exclusive_table_search(exclusive_table::in, pred_id::in,
    exclusive_ids::out) is semidet.

    % As for search, but aborts if no exclusivity declarations are found.
    %
:- pred exclusive_table_lookup(exclusive_table::in, pred_id::in,
    exclusive_ids::out) is det.

    % Optimises the exclusive_table.
    %
:- pred exclusive_table_optimize(exclusive_table::in, exclusive_table::out)
    is det.

    % Add to the exclusive table that pred_id is used in the exclusivity
    % declaration exclusive_id.
    %
:- pred exclusive_table_add(pred_id::in, exclusive_id::in,
    exclusive_table::in, exclusive_table::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- type exclusive_table     ==  multi_map(pred_id, exclusive_id).

exclusive_table_init(ExclusiveTable) :-
    multi_map.init(ExclusiveTable).

exclusive_table_lookup(ExclusiveTable, PredId, ExclusiveIds) :-
    multi_map.lookup(ExclusiveTable, PredId, ExclusiveIds).

exclusive_table_search(ExclusiveTable, Id, ExclusiveIds) :-
    multi_map.search(ExclusiveTable, Id, ExclusiveIds).

exclusive_table_optimize(ExclusiveTable0, ExclusiveTable) :-
    multi_map.optimize(ExclusiveTable0, ExclusiveTable).

exclusive_table_add(ExclusiveId, PredId, ExclusiveTable0, ExclusiveTable) :-
    multi_map.set(ExclusiveTable0, PredId, ExclusiveId, ExclusiveTable).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "hlds_data.m".

%-----------------------------------------------------------------------------%
:- end_module hlds.hlds_data.
%-----------------------------------------------------------------------------%
