%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2003-2009 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: equiv_type_hlds.m.
% Main author: stayl.
%
% Expand all types in the module_info using all equivalence type definitions,
% even those local to (transitively) imported modules.
%
% This is necessary to avoid problems with back-ends that don't support
% equivalence types properly (or at all).
%
%-----------------------------------------------------------------------------%

:- module transform_hlds.equiv_type_hlds.
:- interface.

:- import_module hlds.hlds_module.

%-----------------------------------------------------------------------------%

:- pred replace_in_hlds(module_info::in, module_info::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module check_hlds.polymorphism.
:- import_module check_hlds.type_util.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_rtti.
:- import_module hlds.instmap.
:- import_module hlds.quantification.
:- import_module libs.compiler_util.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.equiv_type.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_type_subst.
:- import_module recompilation.

:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module svmap.
:- import_module svset.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

replace_in_hlds(!ModuleInfo) :-
    module_info_get_type_table(!.ModuleInfo, TypeTable0),
    foldl2_over_type_ctor_defns(add_type_to_eqv_map, TypeTable0,
        map.init, EqvMap, set.init, EqvExportTypes),
    set.fold(mark_eqv_exported_types, EqvExportTypes, TypeTable0, TypeTable1),

    module_info_get_maybe_recompilation_info(!.ModuleInfo, MaybeRecompInfo0),
    module_info_get_name(!.ModuleInfo, ModuleName),
    map_foldl_over_type_ctor_defns(replace_in_type_defn(ModuleName, EqvMap),
        TypeTable1, TypeTable, MaybeRecompInfo0, MaybeRecompInfo),
    module_info_set_type_table(TypeTable, !ModuleInfo),
    module_info_set_maybe_recompilation_info(MaybeRecompInfo, !ModuleInfo),

    module_info_get_inst_table(!.ModuleInfo, Insts0),
    InstCache0 = map.init,
    replace_in_inst_table(EqvMap, Insts0, Insts, InstCache0, InstCache),
    module_info_set_inst_table(Insts, !ModuleInfo),

    module_info_get_cons_table(!.ModuleInfo, ConsTable0),
    replace_in_cons_table(EqvMap, ConsTable0, ConsTable),
    module_info_set_cons_table(ConsTable, !ModuleInfo),

    module_info_predids(PredIds, !ModuleInfo),
    list.foldl2(replace_in_pred(EqvMap), PredIds, !ModuleInfo, InstCache, _).

%-----------------------------------------------------------------------------%

:- pred add_type_to_eqv_map(type_ctor::in, hlds_type_defn::in,
    eqv_map::in, eqv_map::out, set(type_ctor)::in, set(type_ctor)::out)
    is det.

add_type_to_eqv_map(TypeCtor, Defn, !EqvMap, !EqvExportTypes) :-
    hlds_data.get_type_defn_body(Defn, Body),
    (
        Body = hlds_eqv_type(EqvType),
        hlds_data.get_type_defn_tvarset(Defn, TVarSet),
        hlds_data.get_type_defn_tparams(Defn, Params),
        hlds_data.get_type_defn_status(Defn, Status),
        svmap.det_insert(TypeCtor, eqv_type_body(TVarSet, Params, EqvType),
            !EqvMap),
        IsExported = status_is_exported(Status),
        (
            IsExported = yes,
            add_type_ctors_to_set(EqvType, !EqvExportTypes)
        ;
            IsExported = no
        )
    ;
        ( Body = hlds_du_type(_, _, _, _, _, _, _, _)
        ; Body = hlds_foreign_type(_)
        ; Body = hlds_solver_type(_, _)
        ; Body = hlds_abstract_type(_)
        )
    ).

:- pred add_type_ctors_to_set(mer_type::in,
    set(type_ctor)::in, set(type_ctor)::out) is det.

add_type_ctors_to_set(Type, !Set) :-
    ( type_to_ctor_and_args(Type, TypeCtor, Args) ->
        svset.insert(TypeCtor, !Set),
        list.foldl(add_type_ctors_to_set, Args, !Set)
    ;
        true
    ).

%-----------------------------------------------------------------------------%

:- pred mark_eqv_exported_types(type_ctor::in, type_table::in, type_table::out)
    is det.

mark_eqv_exported_types(TypeCtor, !TypeTable) :-
    ( search_type_ctor_defn(!.TypeTable, TypeCtor, TypeDefn0) ->
        set_type_defn_in_exported_eqv(yes, TypeDefn0, TypeDefn),
        replace_type_ctor_defn(TypeCtor, TypeDefn, !TypeTable)
    ;
        % We can get here for builtin `types' such as func. Since their unify
        % and compare preds are in the runtime system, not generated by the
        % compiler, marking them as exported in the compiler is moot.
        true
    ).

%-----------------------------------------------------------------------------%

:- pred replace_in_type_defn(module_name::in, eqv_map::in, type_ctor::in,
    hlds_type_defn::in, hlds_type_defn::out,
    maybe(recompilation_info)::in, maybe(recompilation_info)::out) is det.

replace_in_type_defn(ModuleName, EqvMap, TypeCtor, !Defn, !MaybeRecompInfo) :-
    hlds_data.get_type_defn_tvarset(!.Defn, TVarSet0),
    hlds_data.get_type_defn_body(!.Defn, Body0),
    TypeCtor = type_ctor(TypeCtorSymName, _TypeCtorArity),
    TypeCtorItem = type_ctor_to_item_name(TypeCtor),
    maybe_start_recording_expanded_items(ModuleName, TypeCtorSymName,
        !.MaybeRecompInfo, EquivTypeInfo0),
    (
        Body0 = hlds_du_type(Ctors0, _, _, _, _, _, _, _),
        equiv_type.replace_in_ctors(EqvMap, Ctors0, Ctors,
            TVarSet0, TVarSet, EquivTypeInfo0, EquivTypeInfo),
        Body = Body0 ^ du_type_ctors := Ctors
    ;
        Body0 = hlds_eqv_type(Type0),
        equiv_type.replace_in_type(EqvMap, Type0, Type, _,
            TVarSet0, TVarSet, EquivTypeInfo0, EquivTypeInfo),
        Body = hlds_eqv_type(Type)
    ;
        Body0 = hlds_foreign_type(_),
        EquivTypeInfo = EquivTypeInfo0,
        Body = Body0,
        TVarSet = TVarSet0
    ;
        Body0 = hlds_solver_type(SolverTypeDetails0, UserEq),
        SolverTypeDetails0 = solver_type_details(RepnType0, InitPred,
            GroundInst, AnyInst, MutableItems),
        equiv_type.replace_in_type(EqvMap, RepnType0, RepnType, _,
            TVarSet0, TVarSet, EquivTypeInfo0, EquivTypeInfo),
        SolverTypeDetails = solver_type_details(RepnType, InitPred,
            GroundInst, AnyInst, MutableItems),
        Body = hlds_solver_type(SolverTypeDetails, UserEq)
    ;
        Body0 = hlds_abstract_type(_),
        EquivTypeInfo = EquivTypeInfo0,
        Body = Body0,
        TVarSet = TVarSet0
    ),
    ItemId = item_id(type_body_item, TypeCtorItem),
    equiv_type.finish_recording_expanded_items(ItemId, EquivTypeInfo,
        !MaybeRecompInfo),
    hlds_data.set_type_defn_body(Body, !Defn),
    hlds_data.set_type_defn_tvarset(TVarSet, !Defn).

:- pred replace_in_inst_table(eqv_map::in,
    inst_table::in, inst_table::out, inst_cache::in, inst_cache::out) is det.

replace_in_inst_table(EqvMap, !InstTable, !Cache) :-
%   %
%   % We currently have no syntax for typed user-defined insts,
%   % so this is unnecessary.
%   %
%   inst_table_get_user_insts(!.InstTable, UserInsts0),
%   map.map_values(
%       (pred(_::in, Defn0::in, Defn::out) is det :-
%           Body0 = Defn0 ^ inst_body,
%           (
%               Body0 = abstract_inst,
%               Defn = Defn0
%           ;
%               Body0 = eqv_inst(Inst0),
%               % XXX We don't have a valid tvarset here.
%               TVarSet0 = varset.init.
%               replace_in_inst(EqvMap, Inst0, Inst,
%                   TVarSet0, _)
%           )
%       ). UserInsts0, UserInsts),
%   inst_table_set_user_insts(!.InstTable, UserInsts, !:InstTable),

    inst_table_get_unify_insts(!.InstTable, UnifyInsts0),
    inst_table_get_merge_insts(!.InstTable, MergeInsts0),
    inst_table_get_ground_insts(!.InstTable, GroundInsts0),
    inst_table_get_any_insts(!.InstTable, AnyInsts0),
    inst_table_get_shared_insts(!.InstTable, SharedInsts0),
    inst_table_get_mostly_uniq_insts(!.InstTable, MostlyUniqInsts0),
    replace_in_inst_table(replace_in_maybe_inst_det(EqvMap),
        EqvMap, UnifyInsts0, UnifyInsts, !Cache),
    replace_in_merge_inst_table(EqvMap, MergeInsts0, MergeInsts, !Cache),
    replace_in_inst_table(replace_in_maybe_inst_det(EqvMap),
        EqvMap, GroundInsts0, GroundInsts, !Cache),
    replace_in_inst_table(replace_in_maybe_inst_det(EqvMap),
        EqvMap, AnyInsts0, AnyInsts, !Cache),
    replace_in_inst_table(replace_in_maybe_inst(EqvMap),
        EqvMap, SharedInsts0, SharedInsts, !Cache),
    replace_in_inst_table(replace_in_maybe_inst(EqvMap),
        EqvMap, MostlyUniqInsts0, MostlyUniqInsts, !.Cache, _),
    inst_table_set_unify_insts(UnifyInsts, !InstTable),
    inst_table_set_merge_insts(MergeInsts, !InstTable),
    inst_table_set_ground_insts(GroundInsts, !InstTable),
    inst_table_set_any_insts(AnyInsts, !InstTable),
    inst_table_set_shared_insts(SharedInsts, !InstTable),
    inst_table_set_mostly_uniq_insts(MostlyUniqInsts, !InstTable).

:- pred replace_in_inst_table(
    pred(T, T, inst_cache, inst_cache)::(pred(in, out, in, out) is det),
    eqv_map::in, map(inst_name, T)::in, map(inst_name, T)::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_inst_table(P, EqvMap, Map0, Map, !Cache) :-
    map.to_assoc_list(Map0, AL0),
    list.map_foldl(
        (pred((Name0 - T0)::in, (Name - T)::out,
                !.Cache::in, !:Cache::out) is det :-
            % XXX We don't have a valid tvarset here.
            varset.init(TVarSet),
            replace_in_inst_name(EqvMap, Name0, Name, _, TVarSet, _, !Cache),
            P(T0, T, !Cache)
        ), AL0, AL, !Cache),
    map.from_assoc_list(AL, Map).

:- pred replace_in_merge_inst_table(eqv_map::in, merge_inst_table::in,
    merge_inst_table::out, inst_cache::in, inst_cache::out) is det.

replace_in_merge_inst_table(EqvMap, Map0, Map, !Cache) :-
    map.to_assoc_list(Map0, AL0),
    list.map_foldl(
        (pred(((InstA0 - InstB0) - MaybeInst0)::in,
                ((InstA - InstB) - MaybeInst)::out,
                !.Cache::in, !:Cache::out) is det :-
            some [!TVarSet] (
                % XXX We don't have a valid tvarset here.
                !:TVarSet = varset.init,
                replace_in_inst(EqvMap, InstA0, InstA, _, !TVarSet, !Cache),
                replace_in_inst(EqvMap, InstB0, InstB, _, !.TVarSet, _,
                    !Cache),
                replace_in_maybe_inst(EqvMap, MaybeInst0, MaybeInst, !Cache)
            )
        ), AL0, AL, !Cache),
    map.from_assoc_list(AL, Map).

:- pred replace_in_maybe_inst(eqv_map::in, maybe_inst::in, maybe_inst::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_maybe_inst(_, inst_unknown, inst_unknown, !Cache).
replace_in_maybe_inst(EqvMap, inst_known(Inst0), inst_known(Inst), !Cache) :-
    % XXX We don't have a valid tvarset here.
    varset.init(TVarSet),
    replace_in_inst(EqvMap, Inst0, Inst, _, TVarSet, _, !Cache).

:- pred replace_in_maybe_inst_det(eqv_map::in,
    maybe_inst_det::in, maybe_inst_det::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_maybe_inst_det(_, inst_det_unknown, inst_det_unknown, !Cache).
replace_in_maybe_inst_det(EqvMap, inst_det_known(Inst0, Det),
        inst_det_known(Inst, Det), !Cache) :-
    % XXX We don't have a valid tvarset here.
    varset.init(TVarSet),
    replace_in_inst(EqvMap, Inst0, Inst, _, TVarSet, _, !Cache).

%-----------------------------------------------------------------------------%

:- pred replace_in_cons_table(eqv_map::in, cons_table::in, cons_table::out)
    is det.

replace_in_cons_table(EqvMap, !ConsTable) :-
    map.map_values_only(replace_in_cons_defns(EqvMap), !ConsTable).

:- pred replace_in_cons_defns(eqv_map::in,
    list(hlds_cons_defn)::in, list(hlds_cons_defn)::out) is det.

replace_in_cons_defns(EqvMap, !ConsDefns) :-
    list.map(replace_in_cons_defn(EqvMap), !ConsDefns).

:- pred replace_in_cons_defn(eqv_map::in,
    hlds_cons_defn::in, hlds_cons_defn::out) is det.

replace_in_cons_defn(EqvMap, ConsDefn0, ConsDefn) :-
    ConsDefn0 = hlds_cons_defn(TypeCtor, TVarSet0, TypeParams, KindMap,
        ExistQTVars, ProgConstraints, ConstructorArgs0, Context),
    list.map_foldl(replace_in_constructor_arg(EqvMap),
        ConstructorArgs0, ConstructorArgs, TVarSet0, TVarSet),
    ConsDefn = hlds_cons_defn(TypeCtor, TVarSet, TypeParams, KindMap,
        ExistQTVars, ProgConstraints, ConstructorArgs, Context).

:- pred replace_in_constructor_arg(eqv_map::in,
    constructor_arg::in, constructor_arg::out,
    tvarset::in, tvarset::out) is det.

replace_in_constructor_arg(EqvMap, CtorArg0, CtorArg, !TVarSet) :-
    CtorArg0 = ctor_arg(MaybeFieldName, Type0, Context),
    replace_in_type(EqvMap, Type0, Type, _Changed, !TVarSet, no, _),
    CtorArg = ctor_arg(MaybeFieldName, Type, Context).

%-----------------------------------------------------------------------------%

:- pred replace_in_pred(eqv_map::in, pred_id::in,
    module_info::in, module_info::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_pred(EqvMap, PredId, !ModuleInfo, !Cache) :-
    some [!PredInfo, !EquivTypeInfo] (
        module_info_get_name(!.ModuleInfo, ModuleName),
        module_info_pred_info(!.ModuleInfo, PredId, !:PredInfo),
        module_info_get_maybe_recompilation_info(!.ModuleInfo,
            MaybeRecompInfo0),

        PredName = pred_info_name(!.PredInfo),
        maybe_start_recording_expanded_items(ModuleName,
            qualified(ModuleName, PredName), MaybeRecompInfo0,
            !:EquivTypeInfo),

        pred_info_get_arg_types(!.PredInfo, ArgTVarSet0, ExistQVars,
            ArgTypes0),
        equiv_type.replace_in_type_list(EqvMap, ArgTypes0, ArgTypes,
            _, ArgTVarSet0, ArgTVarSet1, !EquivTypeInfo),

        % The constraint_proofs aren't used after polymorphism,
        % so they don't need to be processed.
        pred_info_get_class_context(!.PredInfo, ClassContext0),
        equiv_type.replace_in_prog_constraints(EqvMap, ClassContext0,
            ClassContext, ArgTVarSet1, ArgTVarSet, !EquivTypeInfo),
        pred_info_set_class_context(ClassContext, !PredInfo),
        pred_info_set_arg_types(ArgTVarSet, ExistQVars, ArgTypes, !PredInfo),

        ItemId = item_id(pred_or_func_to_item_type(
            pred_info_is_pred_or_func(!.PredInfo)),
            item_name(qualified(pred_info_module(!.PredInfo), PredName),
                pred_info_orig_arity(!.PredInfo))),
        equiv_type.finish_recording_expanded_items(ItemId,
            !.EquivTypeInfo, MaybeRecompInfo0, MaybeRecompInfo),
        module_info_set_maybe_recompilation_info(MaybeRecompInfo, !ModuleInfo),

        pred_info_get_procedures(!.PredInfo, ProcMap0),
        map.map_values_foldl3(replace_in_proc(EqvMap), ProcMap0, ProcMap,
            !ModuleInfo, !PredInfo, !Cache),
        pred_info_set_procedures(ProcMap, !PredInfo),
        module_info_set_pred_info(PredId, !.PredInfo, !ModuleInfo)
    ).

:- pred replace_in_proc(eqv_map::in, proc_info::in, proc_info::out,
    module_info::in, module_info::out, pred_info::in, pred_info::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_proc(EqvMap, !ProcInfo, !ModuleInfo, !PredInfo, !Cache) :-
    some [!TVarSet] (
        pred_info_get_typevarset(!.PredInfo, !:TVarSet),

        proc_info_get_argmodes(!.ProcInfo, ArgModes0),
        replace_in_modes(EqvMap, ArgModes0, ArgModes, _, !TVarSet, !Cache),
        proc_info_set_argmodes(ArgModes, !ProcInfo),

        proc_info_get_maybe_declared_argmodes(!.ProcInfo, MaybeDeclModes0),
        (
            MaybeDeclModes0 = yes(DeclModes0),
            replace_in_modes(EqvMap, DeclModes0, DeclModes, _, !TVarSet,
                !Cache),
            proc_info_set_maybe_declared_argmodes(yes(DeclModes), !ProcInfo)
        ;
            MaybeDeclModes0 = no
        ),

        proc_info_get_vartypes(!.ProcInfo, VarTypes0),
        map.map_values_foldl(hlds_replace_in_type(EqvMap),
            VarTypes0, VarTypes, !TVarSet),
        proc_info_set_vartypes(VarTypes, !ProcInfo),

        proc_info_get_rtti_varmaps(!.ProcInfo, RttiVarMaps0),
        rtti_varmaps_types(RttiVarMaps0, AllTypes),
        list.foldl2(
            (pred(OldType::in, !.TMap::in, !:TMap::out,
                    !.TVarSet::in, !:TVarSet::out) is det :-
                hlds_replace_in_type(EqvMap, OldType, NewType, !TVarSet),
                svmap.set(OldType, NewType, !TMap)
            ), AllTypes, map.init, TypeMap, !TVarSet),
        rtti_varmaps_transform_types(map.lookup(TypeMap),
            RttiVarMaps0, RttiVarMaps),
        proc_info_set_rtti_varmaps(RttiVarMaps, !ProcInfo),

        proc_info_get_goal(!.ProcInfo, Goal0),
        ReplaceInfo0 = replace_info(!.ModuleInfo, !.PredInfo, !.ProcInfo,
            !.TVarSet, !.Cache, no),
        replace_in_goal(EqvMap, Goal0, Goal, Changed,
            ReplaceInfo0, ReplaceInfo),
        ReplaceInfo = replace_info(!:ModuleInfo, !:PredInfo, !:ProcInfo,
            !:TVarSet, _XXX, Recompute),
        (
            Changed = yes,
            proc_info_set_goal(Goal, !ProcInfo)
        ;
            Changed = no
        ),
        (
            Recompute = yes,
            requantify_proc_general(ordinary_nonlocals_no_lambda, !ProcInfo),
            recompute_instmap_delta_proc(
                do_not_recompute_atomic_instmap_deltas, !ProcInfo, !ModuleInfo)
        ;
            Recompute = no
        ),
        pred_info_set_typevarset(!.TVarSet, !PredInfo)
    ).

%-----------------------------------------------------------------------------%

    % Replace equivalence types in a given type.
    %
:- pred hlds_replace_in_type(eqv_map::in, mer_type::in, mer_type::out,
    tvarset::in, tvarset::out) is det.

hlds_replace_in_type(EqvMap, Type0, Type, !VarSet) :-
    hlds_replace_in_type_2(EqvMap, [], Type0, Type, _Changed, !VarSet).

:- pred hlds_replace_in_type_2(eqv_map::in, list(type_ctor)::in,
    mer_type::in, mer_type::out, bool::out,
    tvarset::in, tvarset::out) is det.

hlds_replace_in_type_2(EqvMap, TypeCtorsAlreadyExpanded,
        Type0, Type, Changed, !VarSet) :-
    (
        ( Type0 = type_variable(_, _)
        ; Type0 = builtin_type(_)
        ),
        Type = Type0,
        Changed = no
    ;
        Type0 = defined_type(SymName, TypeArgs0, Kind),
        hlds_replace_in_type_list_2(EqvMap, TypeCtorsAlreadyExpanded,
            TypeArgs0, TypeArgs, no, ArgsChanged, !VarSet),
        Arity = list.length(TypeArgs),
        TypeCtor = type_ctor(SymName, Arity),
        hlds_replace_type_ctor(EqvMap, TypeCtorsAlreadyExpanded, Type0,
            TypeCtor, TypeArgs, Kind, Type, ArgsChanged, Changed, !VarSet)
    ;
        Type0 = higher_order_type(ArgTypes0, MaybeRetType0, Purity,
            EvalMethod),
        (
            MaybeRetType0 = yes(RetType0),
            hlds_replace_in_type_2(EqvMap, TypeCtorsAlreadyExpanded,
                RetType0, RetType, RetChanged, !VarSet),
            MaybeRetType = yes(RetType)
        ;
            MaybeRetType0 = no,
            MaybeRetType = no,
            RetChanged = no
        ),
        hlds_replace_in_type_list_2(EqvMap, TypeCtorsAlreadyExpanded,
            ArgTypes0, ArgTypes, RetChanged, Changed, !VarSet),
        (
            Changed = yes,
            Type = higher_order_type(ArgTypes, MaybeRetType, Purity,
                EvalMethod)
        ;
            Changed = no,
            Type = Type0
        )
    ;
        Type0 = tuple_type(Args0, Kind),
        hlds_replace_in_type_list_2(EqvMap, TypeCtorsAlreadyExpanded,
            Args0, Args, no, Changed, !VarSet),
        (
            Changed = yes,
            Type = tuple_type(Args, Kind)
        ;
            Changed = no,
            Type = Type0
        )
    ;
        Type0 = apply_n_type(Var, Args0, Kind),
        hlds_replace_in_type_list_2(EqvMap, TypeCtorsAlreadyExpanded,
            Args0, Args, no, Changed, !VarSet),
        (
            Changed = yes,
            Type = apply_n_type(Var, Args, Kind)
        ;
            Changed = no,
            Type = Type0
        )
    ;
        Type0 = kinded_type(RawType0, Kind),
        hlds_replace_in_type_2(EqvMap, TypeCtorsAlreadyExpanded,
            RawType0, RawType, Changed, !VarSet),
        (
            Changed = yes,
            Type = kinded_type(RawType, Kind)
        ;
            Changed = no,
            Type = Type0
        )
    ).

:- pred hlds_replace_in_type_list_2(eqv_map::in, list(type_ctor)::in,
    list(mer_type)::in, list(mer_type)::out, bool::in, bool::out,
    tvarset::in, tvarset::out) is det.

hlds_replace_in_type_list_2(_EqvMap, _Seen, [], [], !Changed, !VarSet).
hlds_replace_in_type_list_2(EqvMap, Seen, [Type0 | Types0], [Type | Types],
        !Changed, !VarSet) :-
    hlds_replace_in_type_2(EqvMap, Seen, Type0, Type, TypeChanged, !VarSet),
    bool.or(!.Changed, TypeChanged, !:Changed),
    hlds_replace_in_type_list_2(EqvMap, Seen, Types0, Types,
        !Changed, !VarSet).

:- pred hlds_replace_type_ctor(eqv_map::in, list(type_ctor)::in, mer_type::in,
    type_ctor::in, list(mer_type)::in, kind::in, mer_type::out,
    bool::in, bool::out, tvarset::in, tvarset::out) is det.

hlds_replace_type_ctor(EqvMap, TypeCtorsAlreadyExpanded0, Type0,
        TypeCtor, ArgTypes, Kind, Type, !Changed, !VarSet) :-
    ( list.member(TypeCtor, TypeCtorsAlreadyExpanded0) ->
        AlreadyExpanded = yes
    ;
        AlreadyExpanded = no
    ),
    (
        map.search(EqvMap, TypeCtor, eqv_type_body(EqvVarSet, Params0, Body0)),

        % Don't merge in the variable names from the type declaration to avoid
        % creating multiple variables with the same name so that
        % `varset.create_name_var_map' can be used on the resulting tvarset.
        % make_hlds uses `varset.create_name_var_map' to match up type
        % variables in `:- pragma type_spec' declarations and explicit type
        % qualifications with the type variables in the predicate's
        % declaration.

        tvarset_merge_renaming_without_names(!.VarSet, EqvVarSet, !:VarSet,
            Renaming),
        AlreadyExpanded = no
    ->
        map.apply_to_list(Params0, Renaming, Params),
        apply_variable_renaming_to_type(Renaming, Body0, Body1),
        map.from_corresponding_lists(Params, ArgTypes, Subst),
        apply_subst_to_type(Subst, Body1, Body),
        TypeCtorsAlreadyExpanded = [TypeCtor | TypeCtorsAlreadyExpanded0],
        hlds_replace_in_type_2(EqvMap, TypeCtorsAlreadyExpanded,
            Body, Type, _BodyChanged, !VarSet),
        !:Changed = yes
    ;
        (
            !.Changed = yes,
            TypeCtor = type_ctor(SymName, _Arity),
            Type = defined_type(SymName, ArgTypes, Kind)
        ;
            !.Changed = no,
            Type = Type0
        )
    ).

%-----------------------------------------------------------------------------%

% Note that we go out of our way to avoid duplicating unchanged
% insts and modes.  This means we don't need to hash-cons those
% insts to avoid losing sharing.

:- pred replace_in_modes(eqv_map::in, list(mer_mode)::in, list(mer_mode)::out,
    bool::out, tvarset::in, tvarset::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_modes(_EqvMap, [], [], no, !TVarSet, !Cache).
replace_in_modes(EqvMap, List0 @ [Mode0 | Modes0], List, Changed,
        !TVarSet, !Cache) :-
    replace_in_mode(EqvMap, Mode0, Mode, Changed0, !TVarSet, !Cache),
    replace_in_modes(EqvMap, Modes0, Modes, Changed1, !TVarSet, !Cache),
    Changed = Changed0 `or` Changed1,
    ( Changed = yes, List = [Mode | Modes]
    ; Changed = no, List = List0
    ).

:- pred replace_in_mode(eqv_map::in, mer_mode::in, mer_mode::out, bool::out,
    tvarset::in, tvarset::out, inst_cache::in, inst_cache::out) is det.

replace_in_mode(EqvMap, Mode0 @ (InstA0 -> InstB0), Mode,
        Changed, !TVarSet, !Cache) :-
    replace_in_inst(EqvMap, InstA0, InstA, ChangedA, !TVarSet, !Cache),
    replace_in_inst(EqvMap, InstB0, InstB, ChangedB, !TVarSet, !Cache),
    Changed = ChangedA `or` ChangedB,
    ( Changed = yes, Mode = (InstA -> InstB)
    ; Changed = no, Mode = Mode0
    ).
replace_in_mode(EqvMap, Mode0 @ user_defined_mode(Name, Insts0), Mode,
        Changed, !TVarSet, !Cache) :-
    replace_in_insts(EqvMap, Insts0, Insts, Changed, !TVarSet, !Cache),
    ( Changed = yes, Mode = user_defined_mode(Name, Insts)
    ; Changed = no, Mode = Mode0
    ).

:- pred replace_in_inst(eqv_map::in, mer_inst::in, mer_inst::out,
    bool::out, tvarset::in, tvarset::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_inst(EqvMap, Inst0, Inst, Changed, !TVarSet, !Cache) :-
    % The call to replace_in_inst_2 can allocate a *lot* of cells if the
    % inst is complex, as it will be for an inst describing a large term.
    % The fact that we traverse the inst twice if ContainsType = yes
    % shouldn't be a problem, since we expect that ContainsType = no
    % almost all the time.

    ContainsType = type_may_occur_in_inst(Inst0),
    (
        ContainsType = yes,
        replace_in_inst_2(EqvMap, Inst0, Inst1, Changed, !TVarSet, !Cache),
        (
            Changed = yes,
            % Doing this when the inst has not changed is too slow,
            % and makes the cache potentially very large.
            hash_cons_inst(Inst1, Inst, !Cache)
        ;
            Changed = no,
            Inst = Inst1
        )
    ;
        ContainsType = no,
        Inst = Inst0,
        Changed = no
    ).

    % Return true if any type may occur inside the given inst.
    %
    % The logic here should be a conservative approximation of the code
    % of replace_in_inst_2.
    %
:- func type_may_occur_in_inst(mer_inst) = bool.

type_may_occur_in_inst(any(_, none)) = no.
type_may_occur_in_inst(any(_, higher_order(_PredInstInfo))) = no.
    % This is a conservative approximation; the mode in _PredInstInfo
    % may contain a reference to a type.
type_may_occur_in_inst(free) = no.
type_may_occur_in_inst(free(_)) = yes.
type_may_occur_in_inst(bound(_, BoundInsts)) =
    type_may_occur_in_bound_insts(BoundInsts).
type_may_occur_in_inst(ground(_, none)) = no.
type_may_occur_in_inst(ground(_, higher_order(_PredInstInfo))) = yes.
    % This is a conservative approximation; the mode in _PredInstInfo
    % may contain a reference to a type.
type_may_occur_in_inst(not_reached) = no.
type_may_occur_in_inst(inst_var(_)) = no.
type_may_occur_in_inst(constrained_inst_vars(_, CInst)) =
    type_may_occur_in_inst(CInst).
type_may_occur_in_inst(defined_inst(_)) = yes.
    % This is also a conservative approximation.
type_may_occur_in_inst(abstract_inst(_, Insts)) =
    type_may_occur_in_insts(Insts).

    % Return true if any type may occur inside any of the given bound insts.
    %
    % The logic here should be a conservative approximation of the code
    % of replace_in_bound_insts.
    %
:- func type_may_occur_in_bound_insts(list(bound_inst)) = bool.

type_may_occur_in_bound_insts([]) = no.
type_may_occur_in_bound_insts([bound_functor(_, Insts) | BoundInsts]) =
    ( type_may_occur_in_insts(Insts) = yes ->
        yes
    ;
        type_may_occur_in_bound_insts(BoundInsts)
    ).

    % Return true if any type may occur inside any of the given insts.
    %
    % The logic here should be a conservative approximation of the code
    % of replace_in_insts.
    %
:- func type_may_occur_in_insts(list(mer_inst)) = bool.

type_may_occur_in_insts([]) = no.
type_may_occur_in_insts([Inst | Insts]) =
    ( type_may_occur_in_inst(Inst) = yes ->
        yes
    ;
        type_may_occur_in_insts(Insts)
    ).

:- pred replace_in_inst_2(eqv_map::in, mer_inst::in, mer_inst::out, bool::out,
    tvarset::in, tvarset::out, inst_cache::in, inst_cache::out) is det.

replace_in_inst_2(_, any(_, none) @ Inst, Inst, no, !TVarSet, !Cache).
replace_in_inst_2(EqvMap, any(Uniq, higher_order(PredInstInfo0)) @ Inst0, Inst,
        Changed, !TVarSet, !Cache) :-
    PredInstInfo0 = pred_inst_info(PorF, Modes0, Det),
    replace_in_modes(EqvMap, Modes0, Modes, Changed, !TVarSet, !Cache),
    (
        Changed = yes,
        Inst = any(Uniq, higher_order(pred_inst_info(PorF, Modes, Det)))
    ;
        Changed = no,
        Inst = Inst0
    ).
replace_in_inst_2(_, free @ Inst, Inst, no, !TVarSet, !Cache).
replace_in_inst_2(EqvMap, free(Type0) @ Inst0, Inst, Changed,
        !TVarSet, !Cache) :-
    equiv_type.replace_in_type(EqvMap, Type0, Type, Changed, !TVarSet, no, _),
    ( Changed = yes, Inst = free(Type)
    ; Changed = no, Inst = Inst0
    ).
replace_in_inst_2(EqvMap, bound(Uniq, BoundInsts0) @ Inst0, Inst,
        Changed, !TVarSet, !Cache) :-
    replace_in_bound_insts(EqvMap, BoundInsts0, BoundInsts, Changed, !TVarSet,
        !Cache),
    ( Changed = yes, Inst = bound(Uniq, BoundInsts)
    ; Changed = no, Inst = Inst0
    ).
replace_in_inst_2(_, ground(_, none) @ Inst, Inst, no, !TVarSet, !Cache).
replace_in_inst_2(EqvMap, ground(Uniq, higher_order(PredInstInfo0)) @ Inst0,
        Inst, Changed, !TVarSet, !Cache) :-
    PredInstInfo0 = pred_inst_info(PorF, Modes0, Det),
    replace_in_modes(EqvMap, Modes0, Modes, Changed, !TVarSet, !Cache),
    (
        Changed = yes,
        Inst = ground(Uniq, higher_order(pred_inst_info(PorF, Modes, Det)))
    ;
        Changed = no,
        Inst = Inst0
    ).
replace_in_inst_2(_, not_reached @ Inst, Inst, no, !TVarSet, !Cache).
replace_in_inst_2(_, inst_var(_) @ Inst, Inst, no, !TVarSet, !Cache).
replace_in_inst_2(EqvMap, constrained_inst_vars(Vars, CInst0) @ Inst0, Inst,
        Changed, !TVarSet, !Cache) :-
    replace_in_inst(EqvMap, CInst0, CInst, Changed, !TVarSet, !Cache),
    ( Changed = yes, Inst = constrained_inst_vars(Vars, CInst)
    ; Changed = no, Inst = Inst0
    ).
replace_in_inst_2(EqvMap, Inst0 @ defined_inst(InstName0), Inst,
         Changed, !TVarSet, !Cache) :-
    replace_in_inst_name(EqvMap, InstName0, InstName, Changed,
        !TVarSet, !Cache),
    ( Changed = yes, Inst = defined_inst(InstName)
    ; Changed = no, Inst = Inst0
    ).
replace_in_inst_2(EqvMap, Inst0 @ abstract_inst(Name, Insts0), Inst,
        Changed, !TVarSet, !Cache) :-
    replace_in_insts(EqvMap, Insts0, Insts, Changed, !TVarSet, !Cache),
    ( Changed = yes, Inst = abstract_inst(Name, Insts)
    ; Changed = no, Inst = Inst0
    ).

:- pred replace_in_inst_name(eqv_map::in, inst_name::in, inst_name::out,
    bool::out, tvarset::in, tvarset::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_inst_name(EqvMap, InstName0 @ user_inst(Name, Insts0), InstName,
        Changed, !TVarSet, !Cache) :-
    replace_in_insts(EqvMap, Insts0, Insts, Changed, !TVarSet, !Cache),
    ( Changed = yes, InstName = user_inst(Name, Insts)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ merge_inst(InstA0, InstB0), InstName,
        Changed, !TVarSet, !Cache) :-
    replace_in_inst(EqvMap, InstA0, InstA, ChangedA, !TVarSet, !Cache),
    replace_in_inst(EqvMap, InstB0, InstB, ChangedB, !TVarSet, !Cache),
    Changed = ChangedA `or` ChangedB,
    ( Changed = yes, InstName = merge_inst(InstA, InstB)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap,
        InstName0 @ unify_inst(Live, InstA0, InstB0, Real),
        InstName, Changed, !TVarSet, !Cache) :-
    replace_in_inst(EqvMap, InstA0, InstA, ChangedA, !TVarSet, !Cache),
    replace_in_inst(EqvMap, InstB0, InstB, ChangedB, !TVarSet, !Cache),
    Changed = ChangedA `or` ChangedB,
    ( Changed = yes, InstName = unify_inst(Live, InstA, InstB, Real)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ ground_inst(Name0, Live, Uniq, Real),
        InstName, Changed, !TVarSet, !Cache) :-
    replace_in_inst_name(EqvMap, Name0, Name, Changed, !TVarSet, !Cache),
    ( Changed = yes, InstName = ground_inst(Name, Live, Uniq, Real)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ any_inst(Name0, Live, Uniq, Real),
        InstName, Changed, !TVarSet, !Cache) :-
    replace_in_inst_name(EqvMap, Name0, Name, Changed, !TVarSet, !Cache),
    ( Changed = yes, InstName = any_inst(Name, Live, Uniq, Real)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ shared_inst(Name0), InstName,
         Changed, !TVarSet, !Cache) :-
    replace_in_inst_name(EqvMap, Name0, Name, Changed, !TVarSet, !Cache),
    ( Changed = yes, InstName = shared_inst(Name)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ mostly_uniq_inst(Name0),
        InstName, Changed, !TVarSet, !Cache) :-
    replace_in_inst_name(EqvMap, Name0, Name, Changed, !TVarSet, !Cache),
    ( Changed = yes, InstName = mostly_uniq_inst(Name)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ typed_ground(Uniq, Type0), InstName,
        Changed, !TVarSet, !Cache) :-
    replace_in_type(EqvMap, Type0, Type, Changed, !TVarSet, no, _),
    ( Changed = yes, InstName = typed_ground(Uniq, Type)
    ; Changed = no, InstName = InstName0
    ).
replace_in_inst_name(EqvMap, InstName0 @ typed_inst(Type0, Name0),
        InstName, Changed, !TVarSet, !Cache) :-
    replace_in_type(EqvMap, Type0, Type, TypeChanged, !TVarSet, no, _),
    replace_in_inst_name(EqvMap, Name0, Name, Changed0, !TVarSet, !Cache),
    Changed = TypeChanged `or` Changed0,
    ( Changed = yes, InstName = typed_inst(Type, Name)
    ; Changed = no, InstName = InstName0
    ).

:- pred replace_in_bound_insts(eqv_map::in, list(bound_inst)::in,
    list(bound_inst)::out, bool::out, tvarset::in, tvarset::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_bound_insts(_EqvMap, [], [], no, !TVarSet, !Cache).
replace_in_bound_insts(EqvMap,
        List0 @ [bound_functor(ConsId, Insts0) | BoundInsts0],
        List, Changed, !TVarSet, !Cache) :-
    replace_in_insts(EqvMap, Insts0, Insts, InstsChanged, !TVarSet, !Cache),
    replace_in_bound_insts(EqvMap, BoundInsts0, BoundInsts,
        BoundInstsChanged, !TVarSet, !Cache),
    Changed = InstsChanged `or` BoundInstsChanged,
    ( Changed = yes, List = [bound_functor(ConsId, Insts) | BoundInsts]
    ; Changed = no, List = List0
    ).

:- pred replace_in_insts(eqv_map::in, list(mer_inst)::in, list(mer_inst)::out,
    bool::out, tvarset::in, tvarset::out,
    inst_cache::in, inst_cache::out) is det.

replace_in_insts(_EqvMap, [], [], no, !TVarSet, !Cache).
replace_in_insts(EqvMap, List0 @ [Inst0 | Insts0], List, Changed,
        !TVarSet, !Cache) :-
    replace_in_inst(EqvMap, Inst0, Inst, Changed0, !TVarSet, !Cache),
    replace_in_insts(EqvMap, Insts0, Insts, Changed1, !TVarSet, !Cache),
    Changed = Changed0 `or` Changed1,
    ( Changed = yes, List = [Inst | Insts]
    ; Changed = no, List = List0
    ).

    % We hash-cons (actually map-cons) insts created by this pass
    % to avoid losing sharing.
:- type inst_cache == map(mer_inst, mer_inst).

:- pred hash_cons_inst(mer_inst::in, mer_inst::out,
    inst_cache::in, inst_cache::out) is det.

hash_cons_inst(Inst0, Inst, !Cache) :-
    ( map.search(!.Cache, Inst0, Inst1) ->
        Inst = Inst1
    ;
        Inst = Inst0,
        !:Cache = map.det_insert(!.Cache, Inst, Inst)
    ).

%-----------------------------------------------------------------------------%

:- type replace_info
    --->    replace_info(
                module_info :: module_info,
                pred_info   :: pred_info,
                proc_info   :: proc_info,
                tvarset     :: tvarset,
                inst_cache  :: inst_cache,
                recompute   :: bool
            ).

:- pred replace_in_goal(eqv_map::in)
    `with_type` replacer(hlds_goal, replace_info)
    `with_inst` replacer.

replace_in_goal(EqvMap, Goal0, Goal, Changed, !Info) :-
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    replace_in_goal_expr(EqvMap, GoalExpr0, GoalExpr, Changed0, !Info),

    InstMapDelta0 = goal_info_get_instmap_delta(GoalInfo0),
    TVarSet0 = !.Info ^ tvarset,
    Cache0 = !.Info ^ inst_cache,
    instmap_delta_map_foldl(
        (pred(_::in, Inst0::in, Inst::out,
                {Changed1, TVarSet1, Cache1}::in,
                {Changed1 `or` InstChanged, TVarSet2, Cache2}::out) is det :-
            replace_in_inst(EqvMap, Inst0, Inst, InstChanged,
                TVarSet1, TVarSet2, Cache1, Cache2)
        ), InstMapDelta0, InstMapDelta,
        {Changed0, TVarSet0, Cache0}, {Changed, TVarSet, Cache}),
    (
        Changed = yes,
        !:Info = !.Info ^ tvarset := TVarSet,
        !:Info = !.Info ^ inst_cache := Cache,
        goal_info_set_instmap_delta(InstMapDelta, GoalInfo0, GoalInfo),
        Goal = hlds_goal(GoalExpr, GoalInfo)
    ;
        Changed = no,
        Goal = Goal0
    ).

:- pred replace_in_case(eqv_map::in)
    `with_type` replacer(case, replace_info)
    `with_inst` replacer.

replace_in_case(EqvMap, Case0, Case, Changed, !Info) :-
    Case0 = case(MainConsId, OtherConsIds, CaseGoal0),
    replace_in_goal(EqvMap, CaseGoal0, CaseGoal, Changed, !Info),
    ( Changed = yes, Case = case(MainConsId, OtherConsIds, CaseGoal)
    ; Changed = no, Case = Case0
    ).

:- pred replace_in_goal_expr(eqv_map::in)
    `with_type` replacer(hlds_goal_expr, replace_info)
    `with_inst` replacer.

replace_in_goal_expr(EqvMap, GoalExpr0, GoalExpr, Changed, !Info) :-
    (
        GoalExpr0 = conj(ConjType, Goals0),
        replace_in_list(replace_in_goal(EqvMap), Goals0, Goals,
            Changed, !Info),
        ( Changed = yes, GoalExpr = conj(ConjType, Goals)
        ; Changed = no, GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = disj(Goals0),
        replace_in_list(replace_in_goal(EqvMap), Goals0, Goals,
            Changed, !Info),
        ( Changed = yes, GoalExpr = disj(Goals)
        ; Changed = no, GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = switch(Var, CanFail, Cases0),
        replace_in_list(replace_in_case(EqvMap), Cases0, Cases,
            Changed, !Info),
        ( Changed = yes, GoalExpr = switch(Var, CanFail, Cases)
        ; Changed = no, GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = negation(NegGoal0),
        replace_in_goal(EqvMap, NegGoal0, NegGoal, Changed, !Info),
        ( Changed = yes, GoalExpr = negation(NegGoal)
        ; Changed = no, GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = scope(Reason, SomeGoal0),
        ( Reason = from_ground_term(_, from_ground_term_construct) ->
            % The code in modes.m sets the kind to from_ground_term_construct
            % only when SomeGoal0 does not have anything to expand.
            GoalExpr = GoalExpr0,
            Changed = no
        ;
            replace_in_goal(EqvMap, SomeGoal0, SomeGoal, Changed, !Info),
            ( Changed = yes, GoalExpr = scope(Reason, SomeGoal)
            ; Changed = no, GoalExpr = GoalExpr0
            )
        )
    ;
        GoalExpr0 = if_then_else(Vars, Cond0, Then0, Else0),
        replace_in_goal(EqvMap, Cond0, Cond, Changed1, !Info),
        replace_in_goal(EqvMap, Then0, Then, Changed2, !Info),
        replace_in_goal(EqvMap, Else0, Else, Changed3, !Info),
        Changed = Changed1 `or` Changed2 `or` Changed3,
        ( Changed = yes, GoalExpr = if_then_else(Vars, Cond, Then, Else)
        ; Changed = no, GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = plain_call(_, _, _, _, _, _),
        GoalExpr = GoalExpr0,
        Changed = no
    ;
        GoalExpr0 = call_foreign_proc(_, _, _, _, _, _, _),
        TVarSet0 = !.Info ^ tvarset,
        replace_in_foreign_arg_list(EqvMap, GoalExpr0 ^ foreign_args,
            Args, ChangedArgs, TVarSet0, TVarSet1, no, _),
        replace_in_foreign_arg_list(EqvMap, GoalExpr0 ^ foreign_extra_args,
            ExtraArgs, ChangedExtraArgs, TVarSet1, TVarSet, no, _),
        Changed = ChangedArgs `or` ChangedExtraArgs,
        (
            Changed = yes,
            !:Info = !.Info ^ tvarset := TVarSet,
            GoalExpr = (GoalExpr0 ^ foreign_args := Args)
                ^ foreign_extra_args := ExtraArgs
        ;
            Changed = no,
            GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = generic_call(Details, Args, Modes0, Detism),
        TVarSet0 = !.Info ^ tvarset,
        Cache0 = !.Info ^ inst_cache,
        replace_in_modes(EqvMap, Modes0, Modes, Changed, TVarSet0, TVarSet,
            Cache0, Cache),
        (
            Changed = yes,
            !:Info = !.Info ^ tvarset := TVarSet,
            !:Info = !.Info ^ inst_cache := Cache,
            GoalExpr = generic_call(Details, Args, Modes, Detism)
        ;
            Changed = no,
            GoalExpr = GoalExpr0
        )
    ;
        GoalExpr0 = unify(Var, _, _, _, _),
        module_info_get_type_table(!.Info ^ module_info, TypeTable),
        proc_info_get_vartypes(!.Info ^ proc_info, VarTypes),
        proc_info_get_rtti_varmaps(!.Info ^ proc_info, RttiVarMaps),
        map.lookup(VarTypes, Var, VarType),
        TypeCtorCat = classify_type(!.Info ^ module_info, VarType),
        (
            % If this goal constructs a type_info for an equivalence type,
            % we need to expand that to make the type_info for the expanded
            % type. It is simpler to just recreate the type_info from scratch.

            GoalExpr0 ^ unify_kind = construct(_, ConsId, _, _, _, _, _),
            ConsId = type_info_cell_constructor(TypeCtor),
            TypeCtorCat = ctor_cat_system(cat_system_type_info),
            search_type_ctor_defn(TypeTable, TypeCtor, TypeDefn),
            hlds_data.get_type_defn_body(TypeDefn, Body),
            Body = hlds_eqv_type(_)
        ->
            Changed = yes,
            pred_info_set_typevarset(!.Info ^ tvarset, !.Info ^ pred_info,
                PredInfo0),
            create_poly_info(!.Info ^ module_info,
                PredInfo0, !.Info ^ proc_info, PolyInfo0),
            rtti_varmaps_var_info(RttiVarMaps, Var, VarInfo),
            (
                VarInfo = type_info_var(TypeInfoType0),
                TypeInfoType = TypeInfoType0
            ;
                ( VarInfo = typeclass_info_var(_)
                ; VarInfo = non_rtti_var
                ),
                unexpected(this_file, "replace_in_goal_expr: info not found")
            ),
            polymorphism_make_type_info_var(TypeInfoType,
                term.context_init, TypeInfoVar, Goals0, PolyInfo0, PolyInfo),
            poly_info_extract(PolyInfo, PredInfo0, PredInfo,
                !.Info ^ proc_info, ProcInfo, ModuleInfo),
            pred_info_get_typevarset(PredInfo, TVarSet),
            !:Info = !.Info ^ pred_info := PredInfo,
            !:Info = !.Info ^ proc_info := ProcInfo,
            !:Info = !.Info ^ module_info := ModuleInfo,
            !:Info = !.Info ^ tvarset := TVarSet,

            rename_vars_in_goals(need_not_rename,
                map.from_assoc_list([TypeInfoVar - Var]), Goals0, Goals),
            ( Goals = [hlds_goal(GoalExpr1, _)] ->
                GoalExpr = GoalExpr1
            ;
                GoalExpr = conj(plain_conj, Goals)
            ),
            !:Info = !.Info ^ recompute := yes
        ;
            % Check for a type_ctor_info for an equivalence type. We can just
            % remove these because after the code above to fix up type_infos
            % for equivalence types they can't be used.

            GoalExpr0 ^ unify_kind = construct(_, ConsId, _, _, _, _, _),
            ConsId = type_info_cell_constructor(TypeCtor),
            TypeCtorCat = ctor_cat_system(cat_system_type_ctor_info),
            search_type_ctor_defn(TypeTable, TypeCtor, TypeDefn),
            hlds_data.get_type_defn_body(TypeDefn, Body),
            Body = hlds_eqv_type(_)
        ->
            Changed = yes,
            GoalExpr = conj(plain_conj, []),
            !:Info = !.Info ^ recompute := yes
        ;
            GoalExpr0 ^ unify_mode = LMode0 - RMode0,
            TVarSet0 = !.Info ^ tvarset,
            Cache0 = !.Info ^ inst_cache,
            replace_in_mode(EqvMap, LMode0, LMode, Changed1,
                TVarSet0, TVarSet1, Cache0, Cache1),
            replace_in_mode(EqvMap, RMode0, RMode, Changed2,
                TVarSet1, TVarSet, Cache1, Cache),
            !:Info = !.Info ^ tvarset := TVarSet,
            !:Info = !.Info ^ inst_cache := Cache,
            replace_in_unification(EqvMap, GoalExpr0 ^ unify_kind, Unification,
                Changed3, !Info),
            Changed = Changed1 `or` Changed2 `or` Changed3,
            (
                Changed = yes,
                GoalExpr1 = GoalExpr0 ^ unify_mode := LMode - RMode,
                GoalExpr = GoalExpr1 ^ unify_kind := Unification
            ;
                Changed = no,
                GoalExpr = GoalExpr0
            )
        )
    ).
replace_in_goal_expr(EqvMap, GoalExpr0, GoalExpr, Changed, !Info) :-
    GoalExpr0 = shorthand(ShortHand0),
    (
        ShortHand0 = atomic_goal(GoalType, Outer, Inner,
            MaybeOutputVars, MainGoal0, OrElseGoals0, OrElseInners),
        replace_in_goal(EqvMap, MainGoal0, MainGoal, Changed1, !Info),
        replace_in_list(replace_in_goal(EqvMap), OrElseGoals0,
            OrElseGoals, Changed2, !Info),
        Changed = Changed1 `or` Changed2,
        (
            Changed = yes,
            ShortHand = atomic_goal(GoalType, Outer, Inner,
                MaybeOutputVars, MainGoal, OrElseGoals, OrElseInners),
            GoalExpr = shorthand(ShortHand)
        ;
            Changed = no,
            GoalExpr = GoalExpr0
        )
    ;
        ShortHand0 = try_goal(MaybeIO, ResultVar, SubGoal0),
        replace_in_goal(EqvMap, SubGoal0, SubGoal, Changed, !Info),
        ShortHand = try_goal(MaybeIO, ResultVar, SubGoal),
        GoalExpr = shorthand(ShortHand)
    ;
        ShortHand0 = bi_implication(_, _),
        unexpected(this_file, "replace_in_goal_expr: bi_implication")
    ).

:- pred replace_in_unification(eqv_map::in)
    `with_type` replacer(unification, replace_info)
    `with_inst` replacer.

replace_in_unification(_, assign(_, _) @ Uni, Uni, no, !Info).
replace_in_unification(_, simple_test(_, _) @ Uni, Uni, no, !Info).
replace_in_unification(EqvMap, Uni0 @ complicated_unify(UniMode0, B, C), Uni,
        Changed, !Info) :-
    replace_in_uni_mode(EqvMap, UniMode0, UniMode, Changed, !Info),
    ( Changed = yes, Uni = complicated_unify(UniMode, B, C)
    ; Changed = no, Uni = Uni0
    ).
replace_in_unification(EqvMap, construct(_, _, _, _, _, _, _) @ Uni0, Uni,
        Changed, !Info) :-
    replace_in_list(replace_in_uni_mode(EqvMap),
        Uni0 ^ construct_arg_modes, UniModes, Changed, !Info),
    ( Changed = yes, Uni = Uni0 ^ construct_arg_modes := UniModes
    ; Changed = no, Uni = Uni0
    ).
replace_in_unification(EqvMap, deconstruct(_, _, _, _, _, _) @ Uni0, Uni,
        Changed, !Info) :-
    replace_in_list(replace_in_uni_mode(EqvMap),
        Uni0 ^ deconstruct_arg_modes, UniModes, Changed, !Info),
    ( Changed = yes, Uni = Uni0 ^ deconstruct_arg_modes := UniModes
    ; Changed = no, Uni = Uni0
    ).

:- pred replace_in_uni_mode(eqv_map::in)
    `with_type` replacer(uni_mode, replace_info)
    `with_inst` replacer.

replace_in_uni_mode(EqvMap, ((InstA0 - InstB0) -> (InstC0 - InstD0)),
        ((InstA - InstB) -> (InstC - InstD)), Changed, !Info) :-
    some [!TVarSet, !Cache] (
        !:TVarSet = !.Info ^ tvarset,
        !:Cache = !.Info ^ inst_cache,
        replace_in_inst(EqvMap, InstA0, InstA, Changed1, !TVarSet, !Cache),
        replace_in_inst(EqvMap, InstB0, InstB, Changed2, !TVarSet, !Cache),
        replace_in_inst(EqvMap, InstC0, InstC, Changed3, !TVarSet, !Cache),
        replace_in_inst(EqvMap, InstD0, InstD, Changed4, !TVarSet, !Cache),
        Changed = Changed1 `or` Changed2 `or` Changed3 `or` Changed4,
        (
            Changed = yes,
            !:Info = (!.Info ^ tvarset := !.TVarSet)
                ^ inst_cache := !.Cache
        ;
            Changed = no
        )
    ).

:- type replacer(T, Acc) == pred(T, T, bool, Acc, Acc).
:- inst replacer == (pred(in, out, out, in, out) is det).

:- pred replace_in_list(replacer(T, Acc)::in(replacer))
    `with_type` replacer(list(T), Acc) `with_inst` replacer.

replace_in_list(_, [], [], no, !Acc).
replace_in_list(Repl, List0 @ [H0 | T0], List, Changed, !Acc) :-
    replace_in_list(Repl, T0, T, Changed0, !Acc),
    Repl(H0, H, Changed1, !Acc),
    Changed = Changed0 `or` Changed1,
    ( Changed = yes, List = [H | T]
    ; Changed = no, List = List0
    ).

%-----------------------------------------------------------------------------%

    % Replace equivalence types in a given type.
    % The bool output is `yes' if anything changed.
    %
:- pred replace_in_foreign_arg(eqv_map::in, foreign_arg::in, foreign_arg::out,
    bool::out, tvarset::in, tvarset::out,
    equiv_type_info::in, equiv_type_info::out) is det.

replace_in_foreign_arg(EqvMap, Arg0, Arg, Changed, !VarSet, !Info) :-
    Arg0 = foreign_arg(Var, NameMode, Type0, BoxPolicy),
    replace_in_type(EqvMap, Type0, Type, Changed, !VarSet, !Info),
    ( Changed = yes, Arg = foreign_arg(Var, NameMode, Type, BoxPolicy)
    ; Changed = no, Arg = Arg0
    ).

:- pred replace_in_foreign_arg_list(eqv_map::in,
    list(foreign_arg)::in, list(foreign_arg)::out, bool::out,
    tvarset::in, tvarset::out, equiv_type_info::in, equiv_type_info::out)
    is det.

replace_in_foreign_arg_list(_EqvMap, [], [], no, !VarSet, !Info).
replace_in_foreign_arg_list(EqvMap, List0 @ [A0 | As0], List,
        Changed, !VarSet, !Info) :-
    replace_in_foreign_arg(EqvMap, A0, A, Changed0, !VarSet, !Info),
    replace_in_foreign_arg_list(EqvMap, As0, As, Changed1, !VarSet, !Info),
    Changed = Changed0 `or` Changed1,
    ( Changed = yes, List = [A | As]
    ; Changed = no, List = List0
    ).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "equiv_type_hlds.m".

%-----------------------------------------------------------------------------%
:- end_module transform_hlds.equiv_type_hlds.
%-----------------------------------------------------------------------------%
