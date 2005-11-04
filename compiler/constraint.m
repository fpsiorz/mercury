%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2001-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: constraint.m
% Main author: stayl.
%
% The constraint propagation transformation attempts to improve the
% efficiency of a generate-and-test style program by statically
% scheduling constraints as early as possible, where a "constraint" is
% any pure goal which has no outputs, can fail, cannot loop and cannot
% throw an exception.
%
%-----------------------------------------------------------------------------%

:- module transform_hlds__constraint.

:- interface.

:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_module.
:- import_module hlds.instmap.
:- import_module parse_tree.prog_data.

:- import_module bool.

%-----------------------------------------------------------------------------%

:- type constraint_info.

    % propagate_constraints_in_goal pushes constraints left and
    % inward within a single goal. Specialized versions of
    % procedures which are called with constrained outputs are
    % created by deforest.m. Goals which deforest.m should try to
    % propagate into calls are annotated with a `constraint' goal
    % feature.
    %
:- pred propagate_constraints_in_goal(hlds_goal::in, hlds_goal::out,
    constraint_info::in, constraint_info::out) is det.

:- pred constraint_info_init(module_info::in, vartypes::in, prog_varset::in,
    instmap::in, constraint_info::out) is det.

:- pred constraint_info_deconstruct(constraint_info::in, module_info::out,
    vartypes::out, prog_varset::out, bool::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.inst_match.
:- import_module check_hlds.mode_util.
:- import_module check_hlds.purity.
:- import_module hlds.goal_form.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_data.
:- import_module hlds.passes_aux.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.

:- import_module assoc_list.
:- import_module list.
:- import_module map.
:- import_module require.
:- import_module set.
:- import_module std_util.
:- import_module string.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

propagate_constraints_in_goal(Goal0, Goal, !Info) :-
    % We need to strip off any existing constraint markers first.
    % Constraint markers are meant to indicate where a constraint is
    % meant to be attached to a call, and that deforest.m should
    % consider creating a specialized version for the call.  If
    % deforest.m rearranges the goal, the constraints may not remain
    % next to the call.
    Goal1 = strip_constraint_markers(Goal0),
    propagate_goal(Goal1, [], Goal, !Info).

:- pred propagate_goal(hlds_goal::in, list(constraint)::in,
    hlds_goal::out, constraint_info::in, constraint_info::out) is det.

propagate_goal(Goal0, Constraints, Goal, !Info) :-
    % We need to treat all single goals as conjunctions so that
    % propagate_conj can move the constraints to the left of the goal
    % if that is allowed.
    Goal0 = _ - GoalInfo0,
    goal_info_get_features(GoalInfo0, Features0),
    goal_info_get_context(GoalInfo0, Context),
    goal_to_conj_list(Goal0, Goals0),
    propagate_conj(Goals0, Constraints, Goals, !Info),
    goal_list_nonlocals(Goals, NonLocals),
    goal_list_instmap_delta(Goals, Delta),
    goal_list_determinism(Goals, ConjDetism),
    goal_list_purity(Goals, Purity),
    goal_info_init(NonLocals, Delta, ConjDetism, purity_pure, Context,
        GoalInfo1),
    goal_info_set_features(Features0, GoalInfo1, GoalInfo2),
    add_goal_info_purity_feature(Purity, GoalInfo2, GoalInfo),
    conj_list_to_goal(Goals, GoalInfo, Goal).

:- pred propagate_conj_sub_goal(hlds_goal::in,
    list(constraint)::in, hlds_goals::out,
    constraint_info::in, constraint_info::out) is det.

propagate_conj_sub_goal(Goal0, Constraints, Goals, !Info) :-
    Goal0 = GoalExpr0 - _,
    ( goal_is_atomic(GoalExpr0) ->
        true
    ;
        % If a non-empty list of constraints is pushed into a sub-goal,
        % quantification, instmap_deltas and determinism need to be
        % recomputed.
        constraint_info_update_changed(Constraints, !Info)
    ),
    InstMap0 = !.Info ^ instmap,
    propagate_conj_sub_goal_2(Goal0, Constraints, Goals, !Info),
    !:Info = !.Info ^ instmap := InstMap0.

:- pred propagate_conj_sub_goal_2(hlds_goal::in, list(constraint)::in,
    list(hlds_goal)::out, constraint_info::in, constraint_info::out)
    is det.

propagate_conj_sub_goal_2(conj(Goals0) - Info, Constraints,
        [conj(Goals) - Info], !Info) :-
    propagate_conj(Goals0, Constraints, Goals, !Info).

propagate_conj_sub_goal_2(disj(Goals0) - Info, Constraints,
        [disj(Goals) - Info], !Info) :-
    propagate_disj(Goals0, Constraints, Goals, !Info).

propagate_conj_sub_goal_2(switch(Var, CanFail, Cases0) - Info,
        Constraints, [switch(Var, CanFail, Cases) - Info], !Info) :-
    propagate_cases(Var, Constraints, Cases0, Cases, !Info).

propagate_conj_sub_goal_2(
        if_then_else(Vars, Cond0, Then0, Else0) - Info,
        Constraints,
        [if_then_else(Vars, Cond, Then, Else) - Info], !Info) :-
    InstMap0 = !.Info ^ instmap,

    % We can't safely propagate constraints into
    % the condition of an if-then-else, because that
    % would change the answers generated by the procedure.
    propagate_goal(Cond0, [], Cond, !Info),
    constraint_info_update_goal(Cond, !Info),
    propagate_goal(Then0, Constraints, Then, !Info),
    !:Info = !.Info ^ instmap := InstMap0,
    propagate_goal(Else0, Constraints, Else, !Info).

    % XXX propagate constraints into par_conjs -- this isn't
    % possible at the moment because par_conj goals must have
    % determinism det.
propagate_conj_sub_goal_2(par_conj(Goals0) - GoalInfo,
        Constraints0,
        [par_conj(Goals) - GoalInfo | Constraints], !Info) :-
    % Propagate constraints within the goals of the conjunction.
    % propagate_disj treats its list of goals as
    % independent rather than specifically disjoint, so we can
    % use it to process a list of independent parallel conjuncts.
    propagate_disj(Goals0, [], Goals, !Info),
    flatten_constraints(Constraints0, Constraints).

propagate_conj_sub_goal_2(scope(Reason, Goal0) - GoalInfo, Constraints,
        [scope(Reason, Goal) - GoalInfo], !Info) :-
    propagate_goal(Goal0, Constraints, Goal, !Info).

propagate_conj_sub_goal_2(not(NegGoal0) - GoalInfo, Constraints0,
        [not(NegGoal) - GoalInfo | Constraints], !Info) :-
    % We can't safely propagate constraints into a negation,
    % because that would change the answers computed by the
    % procedure.
    propagate_goal(NegGoal0, [], NegGoal, !Info),
    flatten_constraints(Constraints0, Constraints).

propagate_conj_sub_goal_2(Goal, Constraints0,
        [Goal | Constraints], !Info) :-
    % propagate_conj will move the constraints
    % to the left of the call if that is possible, so nothing
    % needs to be done here.
    Goal = call(_, _, _, _, _, _) - _,
    flatten_constraints(Constraints0, Constraints).

propagate_conj_sub_goal_2(Goal, Constraints0,
        [Goal | Constraints], !Info) :-
    Goal = generic_call(_, _, _, _) - _,
    flatten_constraints(Constraints0, Constraints).

propagate_conj_sub_goal_2(Goal, Constraints0,
        [Goal | Constraints], !Info) :-
    Goal = foreign_proc(_, _, _, _, _, _) - _,
    flatten_constraints(Constraints0, Constraints).

propagate_conj_sub_goal_2(Goal, _, _, !Info) :-
    Goal = shorthand(_) - _,
    unexpected(this_file, "propagate_conj_sub_goal_2: shorthand").

propagate_conj_sub_goal_2(Goal, Constraints0,
        [Goal | Constraints], !Info) :-
    Goal = unify(_, _, _, _, _) - _,
    flatten_constraints(Constraints0, Constraints).

%-----------------------------------------------------------------------------%

    % Put the constant constructions in front of the constraint.
    %
:- pred flatten_constraints(list(constraint)::in, list(hlds_goal)::out) is det.

flatten_constraints(Constraints0, Goals) :-
    list__map((pred(Constraint::in, Lists::out) is det :-
            Constraint = constraint(Goal, _, _, Constructs),
            Lists = [Constructs, [Goal]]
        ), Constraints0, GoalLists0),
    list__condense(GoalLists0, GoalLists),
    list__condense(GoalLists, Goals).

%-----------------------------------------------------------------------------%

:- pred propagate_disj(list(hlds_goal)::in, list(constraint)::in,
    list(hlds_goal)::out, constraint_info::in, constraint_info::out)
    is det.

propagate_disj([], _, [], !Info).
propagate_disj([Goal0 | Goals0], Constraints, [Goal | Goals], !Info) :-
    InstMap0 = !.Info ^ instmap,
    propagate_goal(Goal0, Constraints, Goal, !Info),
    !:Info = !.Info ^ instmap := InstMap0,
    propagate_disj(Goals0, Constraints, Goals, !Info).

%-----------------------------------------------------------------------------%

:- pred propagate_cases(prog_var::in, list(constraint)::in,
    list(case)::in, list(case)::out,
    constraint_info::in, constraint_info::out) is det.

propagate_cases(_, _, [], [], !Info).
propagate_cases(Var, Constraints, [case(ConsId, Goal0) | Cases0],
        [case(ConsId, Goal) | Cases], !Info) :-
    InstMap0 = !.Info ^ instmap,
    constraint_info_bind_var_to_functor(Var, ConsId, !Info),
    propagate_goal(Goal0, Constraints, Goal, !Info),
    !:Info = !.Info ^ instmap := InstMap0,
    propagate_cases(Var, Constraints, Cases0, Cases, !Info).

%-----------------------------------------------------------------------------%

    % propagate_conj detects the constraints in a conjunction and
    % moves them to as early as possible in the list. Some effort is
    % made to keep the constraints in the same order as they are
    % encountered to increase the likelihood of folding recursive
    % calls.
    %
:- pred propagate_conj(list(hlds_goal)::in, list(constraint)::in,
    list(hlds_goal)::out, constraint_info::in, constraint_info::out)
    is det.

propagate_conj(Goals0, Constraints, Goals, !Info) :-
    constraint_info_update_changed(Constraints, !Info),
    ( Goals0 = [] ->
        flatten_constraints(Constraints, Goals)
    ; Goals0 = [Goal0], Constraints = [] ->
        propagate_conj_sub_goal(Goal0, [], Goals, !Info)
    ;
        InstMap0 = !.Info ^ instmap,
        ModuleInfo = !.Info ^ module_info,
        VarTypes = !.Info ^ vartypes,
        annotate_conj_output_vars(Goals0, ModuleInfo,
            VarTypes, InstMap0, [], RevGoals1),
        annotate_conj_constraints(ModuleInfo, RevGoals1,
            Constraints, [], Goals2, !Info),
        propagate_conj_constraints(Goals2, [], Goals, !Info)
    ).

    % Annotate each conjunct with the variables it produces.
    %
:- pred annotate_conj_output_vars(list(hlds_goal)::in, module_info::in,
    vartypes::in, instmap::in, annotated_conj::in, annotated_conj::out)
    is det.

annotate_conj_output_vars([], _, _, _, !RevGoals).
annotate_conj_output_vars([Goal | Goals], ModuleInfo, VarTypes, InstMap0,
        !RevGoals) :-
    Goal = _ - GoalInfo,
    goal_info_get_instmap_delta(GoalInfo, InstMapDelta),

    instmap__apply_instmap_delta(InstMap0, InstMapDelta, InstMap),
    instmap_changed_vars(InstMap0, InstMap, VarTypes,
        ModuleInfo, ChangedVars0),

    instmap__vars_list(InstMap, InstMapVars),
    %
    % Restrict the set of changed variables down to the set for
    % which the new inst is not an acceptable substitute for the
    % old.  This is done to allow reordering of a goal which uses a
    % variable with inst `ground(shared, no)' with a constraint
    % which just adds information, changing the inst to
    % `bound(shared, ...)'.
    %
    InCompatible = (pred(Var::in) is semidet :-
            instmap__lookup_var(InstMap0, Var, InstBefore),
            instmap_delta_search_var(InstMapDelta, Var, InstAfter),
            \+ inst_matches_initial(InstAfter, InstBefore,
                map__lookup(VarTypes, Var), ModuleInfo)
        ),
    IncompatibleInstVars = set__list_to_set(
        list__filter(InCompatible, InstMapVars)),
    %
    % This will consider variables with inst `any' to be bound by
    % the goal, so goals which have non-locals with inst `any' will
    % not be considered to be constraints. XXX This is too conservative.
    %
    Bound = (pred(Var::in) is semidet :-
            instmap__lookup_var(InstMap0, Var, InstBefore),
            instmap_delta_search_var(InstMapDelta, Var, InstAfter),
            \+ inst_matches_binding(InstAfter, InstBefore,
                map__lookup(VarTypes, Var), ModuleInfo)
        ),
    BoundVars = set__list_to_set(list__filter(Bound, InstMapVars)),

    %
    % Make sure that variables with inst `any' are placed in
    % the changed vars set. XXX This is too conservative, but
    % avoids unexpected reorderings.
    %
    set__union(ChangedVars0, BoundVars, ChangedVars),

    AnnotatedConjunct = annotated_conjunct(Goal, ChangedVars, BoundVars,
        IncompatibleInstVars),
    annotate_conj_output_vars(Goals, ModuleInfo, VarTypes,
        InstMap, [AnnotatedConjunct | !.RevGoals], !:RevGoals).

%-----------------------------------------------------------------------------%

    % Conjunction annotated with the variables each conjunct
    % changes the instantiatedness of.
    %
:- type annotated_conj == list(annotated_conjunct).

:- type annotated_conjunct
    ---> annotated_conjunct(
        hlds_goal,

            % All variables returned by instmap_changed_vars.
        set(prog_var),

            % All variables returned by instmap_changed_vars for
            % which inst_matches_binding(NewInst, OldInst) fails.
        set(prog_var),

            % Variables returned by instmap_changed_vars
            % for which the new inst cannot be substituted
            % for the old as an input to a goal
            % (inst_matches_initial(NewInst, OldInst) fails).
        set(prog_var)
    ).


    % A constraint is a goal that may fail, has no outputs,
    % always terminates and will not throw an exception.
    %
:- type constraint
    ---> constraint(
            % The constraint itself.
        hlds_goal,

            % All variables returned by instmap_changed_vars.
        set(prog_var),

            % Variables returned by instmap_changed_vars
            % for which the new inst cannot be substituted
            % for the old as an input to a goal
            % (inst_matches_initial(NewInst, OldInst) fails).
        set(prog_var),

            % Goals to construct constants used by the constraint.
            % (as in X = 2, Y < X). These need to be propagated
            % with the constraint.
        list(hlds_goal)
    ).

    % Conjunction annotated with constraining goals.
    % 
:- type constrained_conj == assoc_list(hlds_goal, list(constraint)).

    % Pass backwards over the conjunction, annotating each conjunct
    % with the constraints that should be pushed into it.
    % 
:- pred annotate_conj_constraints(module_info::in, annotated_conj::in,
    list(constraint)::in, constrained_conj::in, constrained_conj::out,
    constraint_info::in, constraint_info::out) is det.

annotate_conj_constraints(_, [], Constraints0, Goals0, Goals, !Info) :-
    flatten_constraints(Constraints0, Constraints1),
    list__map((pred(Goal::in, CnstrGoal::out) is det :-
            CnstrGoal = Goal - []
        ), Constraints1, Constraints),
    list__append(Constraints, Goals0, Goals).
annotate_conj_constraints(ModuleInfo,
        [Conjunct | RevConjuncts0],
        Constraints0, Goals0, Goals, !Info) :-
    Conjunct = annotated_conjunct(Goal, ChangedVars, OutputVars,
        IncompatibleInstVars),
    Goal = GoalExpr - GoalInfo,
    goal_info_get_nonlocals(GoalInfo, NonLocals),
    (
        % Propagate goals that can fail and have no output
        % variables.  Propagating cc_nondet goals would be
        % tricky, because we would need to be careful about
        % reordering the constraints (the cc_nondet goal can't
        % be moved before any goals which can fail).
        %
        goal_info_get_determinism(GoalInfo, Detism),
        ( Detism = semidet
        ; Detism = failure
        ),
        %
        % XXX This is probably a bit too conservative. For
        % example, `any->any' moded non-locals are considered
        % to be outputs.
        %
        set__empty(OutputVars),

        % Don't propagate impure goals.
        goal_info_is_pure(GoalInfo),

        % Don't propagate goals that can loop or throw exceptions.. 
        goal_cannot_loop_or_throw(ModuleInfo, Goal)
    ->
        % It's a constraint, add it to the list of constraints
        % to be attached to goals earlier in the conjunction.
        Goals1 = Goals0,
        Constraint = constraint(GoalExpr - GoalInfo, ChangedVars,
            IncompatibleInstVars, []),
        Constraints1 = [Constraint | Constraints0]
    ;
        %
        % Look for a simple goal which some constraint depends
        % on which can be propagated backwards. This handles
        % cases like X = 2, Y < X. This should only be done for
        % goals which result in no execution at runtime, such as
        % construction of static constants. Currently we only
        % allow constructions of zero arity constants.
        %
        % Make a renamed copy of the goal, renaming within the
        % constraint as well, so that a copy of the constant
        % doesn't need to be kept on the stack.
        %
        Goal = unify(_, _, _, Unify, _) - _,
        Unify = construct(ConstructVar, _, [], _, _, _, _)
    ->
        Goals1 = [Goal - [] | Goals0],
        add_constant_construction(ConstructVar, Goal,
            Constraints0, Constraints1, !Info),

        % If the constraint was the only use of the constant,
        % the old goal can be removed. We need to rerun
        % quantification to work that out.
        !:Info = !.Info ^ changed := yes
    ;
        % Prune away the constraints after a goal that cannot
        % succeed -- they can never be executed.
        goal_info_get_determinism(GoalInfo, Detism),
        determinism_components(Detism, _, at_most_zero)
    ->
        constraint_info_update_changed(Constraints0, !Info),
        Constraints1 = [],
        Goals1 = [Goal - [] | Goals0]
    ;
        % Don't propagate constraints into or past impure goals.
        Goal = _ - GoalInfo,
        goal_info_is_impure(GoalInfo)
    ->
        Constraints1 = [],
        flatten_constraints(Constraints0,
            ConstraintGoals),
        list__map(add_empty_constraints, [Goal | ConstraintGoals],
            GoalsAndConstraints),
        list__append(GoalsAndConstraints, Goals0, Goals1)
    ;
        % Don't move goals which can fail before a goal which
        % can loop or throw an exception if `--fully-strict' is set.
        %
        \+ goal_cannot_loop_or_throw(ModuleInfo, Goal),
        module_info_get_globals(ModuleInfo, Globals),
        globals__lookup_bool_option(Globals, fully_strict, yes)
    ->
        filter_dependent_constraints(NonLocals,
            ChangedVars, Constraints0, DependentConstraints,
            IndependentConstraints),
        flatten_constraints(IndependentConstraints,
            IndependentConstraintGoals),
        list__map(add_empty_constraints, IndependentConstraintGoals,
            GoalsAndConstraints),
        Goals1 = [attach_constraints(Goal, DependentConstraints)
                | GoalsAndConstraints] ++ Goals0,
        Constraints1 = []
    ;
        filter_dependent_constraints(NonLocals,
            OutputVars, Constraints0, DependentConstraints,
            IndependentConstraints),
        Constraints1 = IndependentConstraints,
        Goals1 = [attach_constraints(Goal, DependentConstraints)
            | Goals0]
    ),
    annotate_conj_constraints(ModuleInfo, RevConjuncts0,
        Constraints1, Goals1, Goals, !Info).

:- pred add_empty_constraints(hlds_goal::in,
    pair(hlds_goal, list(constraint))::out) is det.

add_empty_constraints(Goal, Goal - []).

:- func attach_constraints(hlds_goal, list(constraint)) =
    pair(hlds_goal, list(constraint)).

attach_constraints(Goal, Constraints0) = Goal - Constraints :-
        ( Goal = call(_, _, _, _, _, _) - _ ->
                Constraints = list__map(
                    (func(constraint(Goal0, B, C, Constructs0)) =
                        constraint(add_constraint_feature(Goal0), B, C,
                            list__map(add_constraint_feature, Constructs0))
                    ), Constraints0)
        ;
                Constraints = Constraints0
        ).

:- func add_constraint_feature(hlds_goal) = hlds_goal.

add_constraint_feature(Goal - GoalInfo0) = Goal - GoalInfo :-
    goal_info_add_feature(constraint, GoalInfo0, GoalInfo).

%-----------------------------------------------------------------------------%

:- pred add_constant_construction(prog_var::in, hlds_goal::in,
    list(constraint)::in, list(constraint)::out,
    constraint_info::in, constraint_info::out) is det.

add_constant_construction(_, _, [], [], !Info).
add_constant_construction(ConstructVar, Construct0,
        [Constraint0 | Constraints0],
        [Constraint | Constraints], !Info) :-
    Constraint0 = constraint(ConstraintGoal0, ChangedVars,
        IncompatibleInstVars, Constructs0),
    (
        ConstraintGoal0 = _ - ConstraintInfo,
        goal_info_get_nonlocals(ConstraintInfo,
            ConstraintNonLocals),
        set__member(ConstructVar, ConstraintNonLocals)
    ->
        VarSet0 = !.Info ^ varset,
        VarTypes0 = !.Info ^ vartypes,
        varset__new_var(VarSet0, NewVar, VarSet),
        map__lookup(VarTypes0, ConstructVar, VarType),
        map__det_insert(VarTypes0, NewVar, VarType, VarTypes),
        !:Info = !.Info ^ varset := VarSet,
        !:Info = !.Info ^ vartypes := VarTypes,
        map__from_assoc_list([ConstructVar - NewVar], Subn),
        rename_vars_in_goal(Subn, Construct0, Construct),
        Constructs = [Construct | Constructs0],
        rename_vars_in_goal(Subn, ConstraintGoal0, ConstraintGoal),
        Constraint = constraint(ConstraintGoal, ChangedVars,
            IncompatibleInstVars, Constructs)
    ;
        Constraint = Constraint0
    ),
    add_constant_construction(ConstructVar, Construct0,
        Constraints0, Constraints, !Info).

%-----------------------------------------------------------------------------%

    % constraints__filter_dependent_constraints(GoalNonLocals,
    %   GoalOutputVars, Constraints, DependentConstraints,
    %   IndependentConstraints)
    %
    % Find all constraints which depend on the output variables of
    % the current goal in the conjunction being processed.  The
    % DependentConstraints should be pushed into the current goal.
    % The IndependentConstraints should be moved to the left of the
    % current goal, if the purity and termination properties of the
    % current goal allow that.
    %
:- pred filter_dependent_constraints(set(prog_var)::in, set(prog_var)::in,
    list(constraint)::in, list(constraint)::out, list(constraint)::out)
    is det.

filter_dependent_constraints(NonLocals, GoalOutputVars, Constraints,
        Dependent, Independent) :-
    filter_dependent_constraints(NonLocals, GoalOutputVars, Constraints,
        [], RevDependent, [], RevIndependent),
    list__reverse(RevDependent, Dependent),
    list__reverse(RevIndependent, Independent).

:- pred filter_dependent_constraints(set(prog_var)::in, set(prog_var)::in,
    list(constraint)::in,
    list(constraint)::in, list(constraint)::out,
    list(constraint)::in, list(constraint)::out) is det.

filter_dependent_constraints(_NonLocals, _OutputVars, [],
        !RevDependent, !RevIndependent).
filter_dependent_constraints(NonLocals, GoalOutputVars,
        [Constraint | Constraints], !RevDependent, !RevIndependent) :-
    Constraint = constraint(ConstraintGoal, _, IncompatibleInstVars, _),
    ConstraintGoal = _ - ConstraintGoalInfo,
    goal_info_get_nonlocals(ConstraintGoalInfo, ConstraintNonLocals),

    (
        (
            %
            % A constraint is not independent of a goal
            % if it uses any of the output variables
            % of that goal.
            %
            set__intersect(ConstraintNonLocals, GoalOutputVars,
                OutputVarsUsedByConstraint),
            \+ set__empty(OutputVarsUsedByConstraint)
        ;
            %
            % A constraint is not independent of a goal
            % if it changes the inst of a non-local of the goal
            % in such a way that the new inst is incompatible
            % with the old inst (e.g. by losing uniqueness),
            %
            set__intersect(NonLocals, IncompatibleInstVars,
                IncompatibleInstVarsUsedByGoal),
            \+ set__empty(IncompatibleInstVarsUsedByGoal)
        ;
            %
            % A constraint is not independent of a goal if
            % it uses any variables whose instantiatedness is
            % changed by any the of the constraints already
            % attached to the goal (the dependent constraints
            % will be attached to the goal to be pushed into
            % it by propagate_conj_sub_goal).
            %
            list__member(EarlierConstraint, !.RevDependent),
            \+ can_reorder_constraints(EarlierConstraint,
                Constraint)
        )
    ->
        !:RevDependent = [Constraint | !.RevDependent]
    ;
        !:RevIndependent = [Constraint | !.RevIndependent]
    ),
    filter_dependent_constraints(NonLocals, GoalOutputVars, Constraints,
        !RevDependent, !RevIndependent).

%-----------------------------------------------------------------------------%

:- pred can_reorder_constraints(constraint::in, constraint::in) is semidet.

can_reorder_constraints(EarlierConstraint, Constraint) :-
    EarlierConstraint = constraint(_, EarlierChangedVars, _, _),
    Constraint = constraint(ConstraintGoal, _, _, _),
    ConstraintGoal = _ - ConstraintGoalInfo,
    goal_info_get_nonlocals(ConstraintGoalInfo, ConstraintNonLocals),
    set__intersect(EarlierChangedVars, ConstraintNonLocals,
        EarlierConstraintIntersection),
    set__empty(EarlierConstraintIntersection).

%-----------------------------------------------------------------------------%

    % Push the constraints into each conjunct.
    %
:- pred propagate_conj_constraints(constrained_conj::in,
    list(hlds_goal)::in, list(hlds_goal)::out,
    constraint_info::in, constraint_info::out) is det.

propagate_conj_constraints([], RevGoals, Goals, !Info) :-
    list__reverse(RevGoals, Goals).
propagate_conj_constraints([Goal0 - Constraints0 | Goals0],
        RevGoals0, RevGoals, !Info) :-
    filter_complex_constraints(Constraints0,
        SimpleConstraints, ComplexConstraints0),
    propagate_conj_sub_goal(Goal0, SimpleConstraints, GoalList1, !Info),
    flatten_constraints(ComplexConstraints0, ComplexConstraints),
    list__reverse(ComplexConstraints, RevComplexConstraints),
    list__reverse(GoalList1, RevGoalList1),
    list__condense([RevComplexConstraints, RevGoalList1, RevGoals0],
        RevGoals1),
    constraint_info_update_goal(Goal0, !Info),
    propagate_conj_constraints(Goals0, RevGoals1, RevGoals, !Info).

:- pred filter_complex_constraints(list(constraint)::in,
    list(constraint)::out, list(constraint)::out) is det.

filter_complex_constraints(Constraints,
        SimpleConstraints, ComplexConstraints) :-
    filter_complex_constraints(Constraints,
        [], RevSimpleConstraints, [], RevComplexConstraints),
    SimpleConstraints = list__reverse(RevSimpleConstraints),
    ComplexConstraints = list__reverse(RevComplexConstraints).

    % Don't attempt to push branched goals into other goals.
    %
:- pred filter_complex_constraints(list(constraint)::in,
    list(constraint)::in, list(constraint)::out,
    list(constraint)::in, list(constraint)::out) is det.

filter_complex_constraints([], !RevSimpleConstraints, !RevComplexConstraints).
filter_complex_constraints([Constraint | Constraints],
        !RevSimpleConstraints, !RevComplexConstraints) :-
    Constraint = constraint(ConstraintGoal, _, _, _),
    (
        goal_is_simple(ConstraintGoal),

        %
        % Check whether this simple constraint can be reordered
        % with the complex constraints we've already found.
        %
        \+ (
            list__member(ComplexConstraint,
                !.RevComplexConstraints),
            \+ can_reorder_constraints(ComplexConstraint,
                Constraint)
        )
    ->
        !:RevSimpleConstraints =
            [Constraint | !.RevSimpleConstraints]
    ;
        !:RevComplexConstraints =
            [Constraint | !.RevComplexConstraints]
    ),
    filter_complex_constraints(Constraints, !RevSimpleConstraints,
        !RevComplexConstraints).

:- pred goal_is_simple(hlds_goal::in) is semidet.

goal_is_simple(Goal) :-
    Goal = GoalExpr - _,
    (
        goal_is_atomic(GoalExpr)
    ;
        ( GoalExpr = scope(_, SubGoal)
        ; GoalExpr = not(SubGoal)
        ),
        goal_is_simple(SubGoal)
    ).

%-----------------------------------------------------------------------------%

:- type constraint_info
    ---> constraint_info(
        module_info :: module_info,
        vartypes    :: vartypes,
        varset      :: prog_varset,
        instmap     :: instmap,
        changed     :: bool     % has anything changed.
    ).

constraint_info_init(ModuleInfo, VarTypes, VarSet, InstMap, ConstraintInfo) :-
    ConstraintInfo = constraint_info(ModuleInfo, VarTypes, VarSet,
        InstMap, no).

constraint_info_deconstruct(ConstraintInfo, ModuleInfo,
        VarTypes, VarSet, Changed) :-
    ConstraintInfo = constraint_info(ModuleInfo, VarTypes, VarSet,
        _, Changed).

:- pred constraint_info_update_goal(hlds_goal::in,
    constraint_info::in, constraint_info::out) is det.

constraint_info_update_goal(_ - GoalInfo, !Info) :-
    InstMap0 = !.Info ^ instmap,
    goal_info_get_instmap_delta(GoalInfo, InstMapDelta),
    instmap__apply_instmap_delta(InstMap0, InstMapDelta, InstMap),
    !:Info = !.Info ^ instmap := InstMap.

:- pred constraint_info_bind_var_to_functor(prog_var::in, cons_id::in,
    constraint_info::in, constraint_info::out) is det.

constraint_info_bind_var_to_functor(Var, ConsId, !Info) :-
    InstMap0 = !.Info ^ instmap,
    ModuleInfo0 = !.Info ^ module_info,
    VarTypes = !.Info ^ vartypes,
    map__lookup(VarTypes, Var, Type),
    instmap__bind_var_to_functor(Var, Type, ConsId, InstMap0, InstMap,
        ModuleInfo0, ModuleInfo),
    !:Info = !.Info ^ instmap := InstMap,
    !:Info = !.Info ^ module_info := ModuleInfo.

    % If a non-empty list of constraints is pushed into a sub-goal,
    % quantification, instmap_deltas and determinism need to be
    % recomputed.
    %
:- pred constraint_info_update_changed(list(constraint)::in,
    constraint_info::in, constraint_info::out) is det.

constraint_info_update_changed(Constraints, !Info) :-
    ( Constraints = [] ->
        true
    ;
        !:Info = !.Info ^ changed := yes
    ).

%-----------------------------------------------------------------------------%

    % Remove all `constraint' goal features from the goal_infos
    % of all sub-goals of the given goal.
    %
:- func strip_constraint_markers(hlds_goal) = hlds_goal.

strip_constraint_markers(Goal - GoalInfo0) =
        strip_constraint_markers_expr(Goal) - GoalInfo :-
    ( goal_info_has_feature(GoalInfo0, constraint) ->
        goal_info_remove_feature(constraint, GoalInfo0, GoalInfo)
    ;
        GoalInfo = GoalInfo0
    ).

:- func strip_constraint_markers_expr(hlds_goal_expr) = hlds_goal_expr.

strip_constraint_markers_expr(conj(Goals)) =
        conj(list__map(strip_constraint_markers, Goals)).
strip_constraint_markers_expr(disj(Goals)) =
        disj(list__map(strip_constraint_markers, Goals)).
strip_constraint_markers_expr(switch(Var, CanFail, Cases0)) =
        switch(Var, CanFail, Cases) :-
    Cases = list__map(
            (func(case(ConsId, Goal)) =
            case(ConsId, strip_constraint_markers(Goal))
            ), Cases0).
strip_constraint_markers_expr(not(Goal)) =
        not(strip_constraint_markers(Goal)).
strip_constraint_markers_expr(scope(Reason, Goal)) =
        scope(Reason, strip_constraint_markers(Goal)).
strip_constraint_markers_expr(if_then_else(Vars, If, Then, Else)) =
        if_then_else(Vars, strip_constraint_markers(If),
            strip_constraint_markers(Then),
            strip_constraint_markers(Else)).
strip_constraint_markers_expr(par_conj(Goals)) =
        par_conj(list__map(strip_constraint_markers, Goals)).
strip_constraint_markers_expr(Goal) = Goal :-
    Goal = foreign_proc(_, _, _, _, _, _).
strip_constraint_markers_expr(Goal) = Goal :-
    Goal = generic_call(_, _, _, _).
strip_constraint_markers_expr(Goal) = Goal :-
    Goal = call(_, _, _, _, _, _).
strip_constraint_markers_expr(Goal) = Goal :-
    Goal = unify(_, _, _, _, _).
strip_constraint_markers_expr(Goal) = Goal :-
    Goal = shorthand(_).

%-----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "constraint.m".

%-----------------------------------------------------------------------------%
:- end_module constraint.
%-----------------------------------------------------------------------------%
