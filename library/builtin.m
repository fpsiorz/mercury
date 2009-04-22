%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%---------------------------------------------------------------------------%
% Copyright (C) 1994-2007 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
% 
% File: builtin.m.
% Main author: fjh.
% Stability: low.
% 
% This file is automatically imported into every module.
% It is intended for things that are part of the language,
% but which are implemented just as normal user-level code
% rather than with special coding in the compiler.
% 
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module builtin.
:- interface.

%-----------------------------------------------------------------------------%
%
% Types
%

% The types `character', `int', `float', and `string',
% and tuple types `{}', `{T}', `{T1, T2}', ...
% and the types `pred', `pred(T)', `pred(T1, T2)', `pred(T1, T2, T3)', ...
% and `func(T1) = T2', `func(T1, T2) = T3', `func(T1, T2, T3) = T4', ...
% are builtin and are implemented using special code in the
% type-checker.  (XXX TODO: report an error for attempts to redefine
% these types.)

    % The type c_pointer can be used by predicates that use the
    % C interface.
    %
    % NOTE: we strongly recommend using a `foreign_type' pragma instead
    %       of using this type. 
    %
:- type c_pointer.

%-----------------------------------------------------------------------------%
%
% Insts
%

% The standard insts `free', `ground', and `bound(...)' are builtin
% and are implemented using special code in the parser and mode-checker.
%
% So are the standard unique insts `unique', `unique(...)',
% `mostly_unique', `mostly_unique(...)', and `clobbered'.
%
% Higher-order predicate insts `pred(<modes>) is <detism>'
% and higher-order functions insts `func(<modes>) = <mode> is det'
% are also builtin.

    % The name `dead' is allowed as a synonym for `clobbered'.
    % Similarly `mostly_dead' is a synonym for `mostly_clobbered'.
    %
:- inst dead == clobbered.
:- inst mostly_dead == mostly_clobbered.

    % The `any' inst used for the constraint solver interface is also
    % builtin.  The insts `new' and `old' are allowed as synonyms for
    % `free' and `any', respectively, since some of the literature uses
    % this terminology.
    %
:- inst old == any.
:- inst new == free.

%-----------------------------------------------------------------------------%
%
% Standard modes
%

:- mode unused == free >> free.
:- mode output == free >> ground.
:- mode input  == ground >> ground.

:- mode in  == ground >> ground.
:- mode out == free >> ground.

:- mode in(Inst)  == Inst >> Inst.
:- mode out(Inst) == free >> Inst.
:- mode di(Inst)  == Inst >> clobbered.
:- mode mdi(Inst) == Inst >> mostly_clobbered.

%-----------------------------------------------------------------------------%
%
% Unique modes
%

% XXX These are still not fully implemented.

    % unique output
    %
:- mode uo == free >> unique.

    % unique input
    %
:- mode ui == unique >> unique.

    % destructive input
    %
:- mode di == unique >> clobbered.

%-----------------------------------------------------------------------------%
%
% "Mostly" unique modes
%

% Unique except that that may be referenced again on backtracking.

    % mostly unique output
    %
:- mode muo == free >> mostly_unique.

    % mostly unique input
    %
:- mode mui == mostly_unique >> mostly_unique.

    % mostly destructive input
    %
:- mode mdi == mostly_unique >> mostly_clobbered.

%-----------------------------------------------------------------------------%
%
% Dynamic modes
%
    
    % Solver type modes.
    %
:- mode ia == any >> any.
:- mode oa == free >> any.

    % The modes `no' and `oo' are allowed as synonyms, since some of the
    % literature uses this terminology.
    %
:- mode no == new >> old.
:- mode oo == old >> old.

%-----------------------------------------------------------------------------%
%
% Predicates
%

    % copy/2 makes a deep copy of a data structure.
    % The resulting copy is a `unique' value, so you can use
    % destructive update on it.
    %
:- pred copy(T, T).
:- mode copy(ui, uo) is det.
:- mode copy(in, uo) is det.

    % unsafe_promise_unique/2 is used to promise the compiler that you
    % have a `unique' copy of a data structure, so that you can use
    % destructive update.  It is used to work around limitations in
    % the current support for unique modes.
    % `unsafe_promise_unique(X, Y)' is the same as `Y = X' except that
    % the compiler will assume that `Y' is unique.
    %
    % Note that misuse of this predicate may lead to unsound results: if
    % there is more than one reference to the data in question, i.e. it is
    % not `unique', then the behaviour is undefined.
    % (If you lie to the compiler, the compiler will get its revenge!)
    %
:- func unsafe_promise_unique(T::in) = (T::uo) is det.
:- pred unsafe_promise_unique(T::in, T::uo) is det.

    % A synonym for fail/0; this name is more in keeping with Mercury's
    % declarative style rather than its Prolog heritage.
    %
:- pred false is failure.

%-----------------------------------------------------------------------------%

    % This function is useful for converting polymorphic non-solver type
    % values with inst any to inst ground (the compiler recognises that
    % inst any is equivalent to ground for non-polymorphic non-solver
    % type values.)
    %
    % Do not call this on solver type values unless you are absolutely
    % sure that they are semantically ground.
    %
:- func unsafe_cast_any_to_ground(T::ia) = (T::out) is det.

%-----------------------------------------------------------------------------%

    % A call to the function `promise_only_solution(Pred)' constitutes a
    % promise on the part of the caller that `Pred' has at most one
    % solution, i.e. that `not some [X1, X2] (Pred(X1), Pred(X2), X1 \=
    % X2)'.  `promise_only_solution(Pred)' presumes that this assumption is
    % satisfied, and returns the X for which Pred(X) is true, if there is
    % one.
    %
    % You can use `promise_only_solution' as a way of introducing
    % `cc_multi' or `cc_nondet' code inside a `det' or `semidet' procedure.
    %
    % Note that misuse of this function may lead to unsound results: if the
    % assumption is not satisfied, the behaviour is undefined.  (If you lie
    % to the compiler, the compiler will get its revenge!)
    %
    % NOTE: we recommend using the a `promise_equivalent_solutions' goal
    %       instead of this function.
    %
:- func promise_only_solution(pred(T)) = T.
:- mode promise_only_solution(pred(out) is cc_multi) = out is det.
:- mode promise_only_solution(pred(uo) is cc_multi) = uo is det.
:- mode promise_only_solution(pred(out) is cc_nondet) = out is semidet.
:- mode promise_only_solution(pred(uo) is cc_nondet) = uo is semidet.

    % `promise_only_solution_io' is like `promise_only_solution', but for
    % procedures with unique modes (e.g. those that do IO).
    %
    % A call to `promise_only_solution_io(P, X, IO0, IO)' constitutes a
    % promise on the part of the caller that for the given IO0, there is
    % only one value of `X' and `IO' for which `P(X, IO0, IO)' is true.
    % `promise_only_solution_io(P, X, IO0, IO)' presumes that this
    % assumption is satisfied, and returns the X and IO for which `P(X,
    % IO0, IO)' is true.
    %
    % Note that misuse of this predicate may lead to unsound results: if
    % the assumption is not satisfied, the behaviour is undefined.  (If you
    % lie to the compiler, the compiler will get its revenge!)
    %
    % NOTE: we recommend using a `promise_equivalent_solutions' goal
    %       instead of this predicate.
    %
:- pred promise_only_solution_io(
    pred(T, IO, IO)::in(pred(out, di, uo) is cc_multi), T::out,
    IO::di, IO::uo) is det.

%-----------------------------------------------------------------------------%

    % unify(X, Y) is true iff X = Y.
    %
:- pred unify(T::in, T::in) is semidet.

    % For use in defining user-defined unification predicates.
    % The relation defined by a value of type `unify', must be an
    % equivalence relation; that is, it must be symmetric, reflexive,
    % and transitive.
    %
:- type unify(T) == pred(T, T).
:- inst unify == (pred(in, in) is semidet).

:- type comparison_result
    --->    (=)
    ;       (<)
    ;       (>).

    % compare(Res, X, Y) binds Res to =, <, or > depending on whether
    % X is =, <, or > Y in the standard ordering.
    %
:- pred compare(comparison_result, T, T).
    % Note to implementors: the modes must appear in this order:
    % compiler/higher_order.m depends on it, as does
    % compiler/simplify.m (for the inequality simplification.)
:- mode compare(uo, in, in) is det.
:- mode compare(uo, ui, ui) is det.
:- mode compare(uo, ui, in) is det.
:- mode compare(uo, in, ui) is det.

    % For use in defining user-defined comparison predicates.
    % For a value `ComparePred' of type `compare', the following
    % conditions must hold:
    %
    % - the relation
    %   compare_eq(X, Y) :- ComparePred((=), X, Y).
    %   must be an equivalence relation; that is, it must be symmetric,
    %   reflexive, and transitive.
    %
    % - the relations
    %   compare_leq(X, Y) :-
    %       ComparePred(R, X, Y), (R = (=) ; R = (<)).
    %   compare_geq(X, Y) :-
    %       ComparePred(R, X, Y), (R = (=) ; R = (>)).
    %   must be total order relations: that is they must be antisymmetric,
    %   reflexive and transitive.
    %
:- type compare(T) == pred(comparison_result, T, T).
:- inst compare == (pred(uo, in, in) is det).

    % ordering(X, Y) = R <=> compare(R, X, Y)
    %
:- func ordering(T, T) = comparison_result.

    % The standard inequalities defined in terms of compare/3.
    % XXX The ui modes are commented out because they don't yet work properly.
    %
:- pred T  @<  T.
:- mode in @< in is semidet.
% :- mode ui @< in is semidet.
% :- mode in @< ui is semidet.
% :- mode ui @< ui is semidet.

:- pred T  @=<  T.
:- mode in @=< in is semidet.
% :- mode ui @=< in is semidet.
% :- mode in @=< ui is semidet.
% :- mode ui @=< ui is semidet.

:- pred T  @>  T.
:- mode in @> in is semidet.
% :- mode ui @> in is semidet.
% :- mode in @> ui is semidet.
% :- mode ui @> ui is semidet.

:- pred T  @>=  T.
:- mode in @>= in is semidet.
% :- mode ui @>= in is semidet.
% :- mode in @>= ui is semidet.
% :- mode ui @>= ui is semidet.

    % Values of types comparison_pred/1 and comparison_func/1 are used
    % by predicates and functions which depend on an ordering on a given
    % type, where this ordering is not necessarily the standard ordering.
    % In addition to the type, mode and determinism constraints, a
    % comparison predicate C is expected to obey two other laws.
    % For all X, Y and Z of the appropriate type, and for all
    % comparison_results R:
    %   1) C(X, Y, (>)) if and only if C(Y, X, (<))
    %   2) C(X, Y, R) and C(Y, Z, R) implies C(X, Z, R).
    % Comparison functions are expected to obey analogous laws.
    %
    % Note that binary relations <, > and = can be defined from a
    % comparison predicate or function in an obvious way.  The following
    % facts about these relations are entailed by the above constraints:
    % = is an equivalence relation (not necessarily the usual equality),
    % and the equivalence classes of this relation are totally ordered
    % with respect to < and >.
    %
:- type comparison_pred(T) == pred(T, T, comparison_result).
:- inst comparison_pred(I) == (pred(in(I), in(I), out) is det).
:- inst comparison_pred == comparison_pred(ground).

:- type comparison_func(T) == (func(T, T) = comparison_result).
:- inst comparison_func(I) == (func(in(I), in(I)) = out is det).
:- inst comparison_func == comparison_func(ground).

% In addition, the following predicate-like constructs are builtin:
%
%   :- pred (T = T).
%   :- pred (T \= T).
%   :- pred (pred , pred).
%   :- pred (pred ; pred).
%   :- pred (\+ pred).
%   :- pred (not pred).
%   :- pred (pred -> pred).
%   :- pred (if pred then pred).
%   :- pred (if pred then pred else pred).
%   :- pred (pred => pred).
%   :- pred (pred <= pred).
%   :- pred (pred <=> pred).
%
%   (pred -> pred ; pred).
%   some Vars pred
%   all Vars pred
%   call/N

%-----------------------------------------------------------------------------%
    
    % `semidet_succeed' is exactly the same as `true', exception that
    % the compiler thinks that it is semi-deterministic.  You can use
    % calls to `semidet_succeed' to suppress warnings about determinism
    % declarations that could be stricter.
    %
:- pred semidet_succeed is semidet.

    % `semidet_fail' is like `fail' except that its determinism is semidet
    % rather than failure.
    %
:- pred semidet_fail is semidet.

    % A synonym for semidet_succeed/0.
    %
:- pred semidet_true is semidet.

    % A synonym for semidet_fail/0
    %
:- pred semidet_false is semidet.
    
    % `cc_multi_equal(X, Y)' is the same as `X = Y' except that it
    % is cc_multi rather than det.
    %
:- pred cc_multi_equal(T, T).
:- mode cc_multi_equal(di, uo) is cc_multi.
:- mode cc_multi_equal(in, out) is cc_multi.

    % `impure_true' is like `true' except that it is impure.
    %
:- impure pred impure_true is det.

    % `semipure_true' is like `true' except that that it is semipure.
    %
:- semipure pred semipure_true is det.

%-----------------------------------------------------------------------------%
    
    % dynamic_cast(X, Y) succeeds with Y = X iff X has the same ground type
    % as Y (so this may succeed if Y is of type list(int), say, but not if
    % Y is of type list(T)).
    %
:- pred dynamic_cast(T1::in, T2::out) is semidet.

%-----------------------------------------------------------------------------%

:- implementation.

% Everything below here is not intended to be part of the public interface,
% and will not be included in the Mercury library reference manual.

% This import is needed by the Mercury clauses for semidet_succeed/0
% and semidet_fail/0.
%
:- import_module int.

%-----------------------------------------------------------------------------%

:- interface.
    
    % `get_one_solution' and `get_one_solution_io' are impure alternatives
    % to `promise_one_solution' and `promise_one_solution_io', respectively.
    % They get a solution to the procedure, without requiring any promise
    % that there is only one solution.  However, they can only be used in
    % impure code.
    %
:- impure func get_one_solution(pred(T)) = T.
:-        mode get_one_solution(pred(out) is cc_multi) = out is det.
:-        mode get_one_solution(pred(out) is cc_nondet) = out is semidet.

:- impure pred get_one_solution_io(pred(T, IO, IO), T, IO, IO).
:-        mode get_one_solution_io(pred(out, di, uo) is cc_multi,
        out, di, uo) is det.

    % compare_representation(Result, X, Y):
    %
    % compare_representation is similar to the builtin predicate compare/3,
    % except that it does not abort when asked to compare non-canonical terms.
    %
    % The declarative semantics of compare_representation for unequal
    % non-canonical terms is that the result is either (<) or (>).
    % For equal non-canonical terms the result can be anything.
    %
    % Operationally, the result of compare_representation for non-canonical
    % terms is the same as that for comparing the internal representations
    % of the terms, where the internal representation is that which would be
    % produced by deconstruct.cc.
    %
    % XXX This predicate is not yet implemented for highlevel code.
    % This is the reason it is not in the official part of the interface.
    %
:- pred compare_representation(comparison_result, T, T).
:- mode compare_representation(uo, in, in) is cc_multi.

:- implementation.

%-----------------------------------------------------------------------------%

false :-
    fail.

%-----------------------------------------------------------------------------%

% NOTE: dynamic_cast/2 is handled specially compiler/const_prop.m.
% Any changes here may need to be reflected here.

dynamic_cast(X, Y) :-
    private_builtin.typed_unify(X, Y).

%-----------------------------------------------------------------------------%

    % XXX The calls to unsafe_promise_unique below work around
    % mode checker limitations.
:- pragma promise_pure(promise_only_solution/1).
promise_only_solution(CCPred::(pred(out) is cc_multi)) = (OutVal::out) :-
    impure OutVal = get_one_solution(CCPred).
promise_only_solution(CCPred::(pred(uo) is cc_multi)) = (OutVal::uo) :-
    impure OutVal0 = get_one_solution(CCPred),
    OutVal = unsafe_promise_unique(OutVal0).
promise_only_solution(CCPred::(pred(out) is cc_nondet)) = (OutVal::out) :-
    impure OutVal = get_one_solution(CCPred).
promise_only_solution(CCPred::(pred(uo) is cc_nondet)) = (OutVal::uo) :-
    impure OutVal0 = get_one_solution(CCPred),
    OutVal = unsafe_promise_unique(OutVal0).

get_one_solution(CCPred) = OutVal :-
    impure Pred = cc_cast(CCPred),
    Pred(OutVal).

:- impure func cc_cast(pred(T)) = pred(T).
:- mode cc_cast(pred(out) is cc_nondet) = out(pred(out) is semidet) is det.
:- mode cc_cast(pred(out) is cc_multi) = out(pred(out) is det) is det.

:- pragma foreign_proc("C",
    cc_cast(X :: (pred(out) is cc_multi)) = (Y :: out(pred(out) is det)),
    [will_not_call_mercury, thread_safe, will_not_modify_trail,
        does_not_affect_liveness],
"
    Y = X;
").
:- pragma foreign_proc("C",
    cc_cast(X :: (pred(out) is cc_nondet)) = (Y :: out(pred(out) is semidet)),
    [will_not_call_mercury, thread_safe, will_not_modify_trail,
        does_not_affect_liveness],
"
    Y = X;
").
:- pragma foreign_proc("C#",
    cc_cast(X :: (pred(out) is cc_multi)) = (Y :: out(pred(out) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("C#",
    cc_cast(X :: (pred(out) is cc_nondet)) =
        (Y :: out(pred(out) is semidet)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("Java",
    cc_cast(X :: (pred(out) is cc_multi)) = (Y :: out(pred(out) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("Java",
    cc_cast(X :: (pred(out) is cc_nondet)) = (Y :: out(pred(out) is semidet)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("Erlang",
    cc_cast(X :: (pred(out) is cc_multi)) = (Y :: out(pred(out) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X
").
:- pragma foreign_proc("Erlang",
    cc_cast(X :: (pred(out) is cc_nondet)) = (Y :: out(pred(out) is semidet)),
    [will_not_call_mercury, thread_safe],
"
    Y = X
").

:- pragma promise_pure(promise_only_solution_io/4).
promise_only_solution_io(Pred, X, !IO) :-
    impure get_one_solution_io(Pred, X, !IO).

get_one_solution_io(Pred, X, !IO) :-
    impure DetPred = cc_cast_io(Pred),
    DetPred(X, !IO).

:- impure func cc_cast_io(pred(T, IO, IO)) = pred(T, IO, IO).
:- mode cc_cast_io(pred(out, di, uo) is cc_multi) =
    out(pred(out, di, uo) is det) is det.

:- pragma foreign_proc("C",
    cc_cast_io(X :: (pred(out, di, uo) is cc_multi)) =
        (Y :: out(pred(out, di, uo) is det)),
    [will_not_call_mercury, thread_safe, will_not_modify_trail,
        does_not_affect_liveness],
"
    Y = X;
").
:- pragma foreign_proc("C#",
    cc_cast_io(X :: (pred(out, di, uo) is cc_multi)) =
        (Y :: out(pred(out, di, uo) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("Java",
    cc_cast_io(X :: (pred(out, di, uo) is cc_multi)) =
        (Y :: out(pred(out, di, uo) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X;
").
:- pragma foreign_proc("Erlang",
    cc_cast_io(X :: (pred(out, di, uo) is cc_multi)) =
        (Y :: out(pred(out, di, uo) is det)),
    [will_not_call_mercury, thread_safe],
"
    Y = X
").

%-----------------------------------------------------------------------------%
%
% IMPORTANT: any changes or additions to external predicates should be
% reflected in the definition of pred_is_external in
% mdbcomp/program_representation.m.  The debugger needs to know what predicates
% are defined externally, so that it knows not to expect events for those
% predicates.
%

:- external(unify/2).
:- external(compare/3).
:- external(compare_representation/3).

ordering(X, Y) = R :-
    compare(R, X, Y).

    % simplify.goal automatically inlines these definitions.
    %
X  @< Y :-
    compare((<), X, Y).
X @=< Y :-
    not compare((>), X, Y).
X @>  Y :-
    compare((>), X, Y).
X @>= Y :-
    not compare((<), X, Y).

%-----------------------------------------------------------------------------%

:- pragma foreign_decl("C", "#include ""mercury_type_info.h""").

:- interface.

:- pred call_rtti_generic_unify(T::in, T::in) is semidet.
:- pred call_rtti_generic_compare(comparison_result::out, T::in, T::in) is det.

:- implementation.
:- use_module erlang_rtti_implementation.
:- use_module rtti_implementation.

call_rtti_generic_unify(X, Y) :-
    rtti_implementation.generic_unify(X, Y).
call_rtti_generic_compare(Res, X, Y) :-
    rtti_implementation.generic_compare(Res, X, Y).

:- pragma foreign_code("C#", "
public static void compare_3(object[] TypeInfo_for_T, ref object[] Res,
    object X, object Y)
{
    mercury.builtin.mercury_code.call_rtti_generic_compare_3(TypeInfo_for_T,
        ref Res, X, Y);
}

public static void compare_3_m1(object[] TypeInfo_for_T, ref object[] Res,
    object X, object Y)
{
    compare_3(TypeInfo_for_T, ref Res, X, Y);
}

public static void compare_3_m2(object[] TypeInfo_for_T, ref object[] Res,
    object X, object Y)
{
    compare_3(TypeInfo_for_T, ref Res, X, Y);
}

public static void compare_3_m3(object[] TypeInfo_for_T, ref object[] Res,
    object X, object Y)
{
    compare_3(TypeInfo_for_T, ref Res, X, Y);
}
").

:- pragma foreign_code("C#", "
public static object deep_copy(object o)
{
    System.Type t = o.GetType();

    if (t.IsValueType) {
        return o;
    } else if (t == typeof(string)) {
        // XXX For some reason we need to handle strings specially.
        // It is probably something to do with the fact that they
        // are a builtin type.
        string s;
        s = (string) o;
        return s;
    } else {
        object n;

        // This will do a bitwise shallow copy of the object.
        n = t.InvokeMember(""MemberwiseClone"",
            System.Reflection.BindingFlags.Instance |
            System.Reflection.BindingFlags.NonPublic |
            System.Reflection.BindingFlags.InvokeMethod,
            null, o, new object[] {});

        // Set each of the fields to point to a deep copy of the
        // field.
        deep_copy_fields(t.GetFields(
            System.Reflection.BindingFlags.Public |
            System.Reflection.BindingFlags.Instance),
            n, o);

        // XXX This requires that mercury.dll have
        // System.Security.Permissions.ReflectionPermission
        // so that the non-public fields are accessible.
        deep_copy_fields(t.GetFields(
            System.Reflection.BindingFlags.NonPublic |
            System.Reflection.BindingFlags.Instance),
            n, o);

        return n;
    }
}

public static void deep_copy_fields(System.Reflection.FieldInfo[] fields,
    object dest, object src)
{
    // XXX We don't handle init-only fields, but I can't think of a way.
    foreach (System.Reflection.FieldInfo f in fields)
    {
        f.SetValue(dest, deep_copy(f.GetValue(src)));
    }
}
").

:- pragma foreign_code("C#", "
public static bool unify_2_p(object[] ti, object X, object Y)
{
    return mercury.builtin.mercury_code.call_rtti_generic_unify_2_p(ti, X, Y);
}

").

:- pragma foreign_code("C#", "

public static bool
special__Unify____void_0_0(object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called unify for type `void'"");
    return false;
}

public static bool
special__Unify____c_pointer_0_0(object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called unify for type `c_pointer'"");
    return false;
}

public static bool
special__Unify____func_0_0(object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called unify for `func' type"");
    return false;
}

public static bool
special__Unify____tuple_0_0(object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called unify for `tuple' type"");
    return false;
}

public static void
special__Compare____void_0_0(ref object[] result, object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called compare/3 for type `void'"");
}

public static void
special__Compare____c_pointer_0_0(
    ref object[] result, object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(
        ""called compare/3 for type `c_pointer'"");
}

public static void
special__Compare____func_0_0(ref object[] result, object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called compare/3 for `func' type"");
}

public static void
special__Compare____tuple_0_0(ref object[] result,
    object[] x, object[] y)
{
    mercury.runtime.Errors.fatal_error(""called compare/3 for `tuple' type"");
}
").

:- pragma foreign_code("Java",
"
public static java.lang.Object
deep_copy(java.lang.Object original) {
    java.lang.Object clone;

    if (original == null) {
        return null;
    }

    java.lang.Class cls = original.getClass();

    if (cls.getName().equals(""java.lang.String"")) {
        return new java.lang.String((java.lang.String) original);
    }

    if (cls.isArray()) {
        int length = java.lang.reflect.Array.getLength(original);
        clone = java.lang.reflect.Array.newInstance(
                cls.getComponentType(), length);
        for (int i = 0; i < length; i++) {
            java.lang.Object X, Y;
            X = java.lang.reflect.Array.get(original, i);
            Y = deep_copy(X);
            java.lang.reflect.Array.set(clone, i, Y);
        }
        return clone;
    }

    /*
    ** XXX Two possible approaches are possible here:
    **
    ** 1. Get all mercury objects to implement the Serializable interface.
    **    Then this whole function could be replaced with code that writes
    **    the Object out via an ObjectOutputStream into a byte array (or
    **    something), then reads it back in again, thus creating a copy.
    ** 2. Call cls.getConstructors(), then iterate through the resulting
    **    array until one of them allows instantiation with all parameters
    **    set to 0 or null (or some sort of recursive call that attempts to
    **    instantiate the parameters).
    **    This approach is of course not guaranteed to work all the time.
    **    Then we can just copy the fields across using Reflection.
    **
    ** For now, we're just throwing an exception.
    */

    throw new java.lang.RuntimeException(
        ""deep copy not yet fully implemented"");
}
").

:- pragma foreign_code("Erlang", "

    '__Compare____c_pointer_0_0'(_, _) ->
        throw(""called compare/3 for type `c_pointer'"").

    '__Unify____c_pointer_0_0'(_, _) ->
        throw(""called unify for type `c_pointer'"").

    compare_3_p_0(TypeInfo, X, Y) ->
        mercury__erlang_rtti_implementation:generic_compare_3_p_0(
            TypeInfo, X, Y).

    compare_3_p_1(TypeInfo, X, Y) ->
        compare_3_p_0(TypeInfo, X, Y).

    compare_3_p_2(TypeInfo, X, Y) ->
        compare_3_p_0(TypeInfo, X, Y).

    compare_3_p_3(TypeInfo, X, Y) ->
        compare_3_p_0(TypeInfo, X, Y).

    % XXX what is this supposed to do?
    compare_representation_3_p_0(TypeInfo, X, Y) ->
        compare_3_p_0(TypeInfo, X, Y).

    unify_2_p_0(TypeInfo, X, Y) ->
        mercury__erlang_rtti_implementation:generic_unify_2_p_0(
            TypeInfo, X, Y).

    '__Unify____tuple_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to unify for tuple/0"").

    '__Compare____tuple_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to compare for tuple/0"").

    '__Unify____void_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to unify for void/0"").

    '__Compare____void_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to compare for void/0"").

    '__Unify____func_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to unify for func/0"").

    '__Compare____func_0_0'(X, Y) ->
        mercury__require:error_1_p_0(""call to compare for func/0"").
").


%-----------------------------------------------------------------------------%

% unsafe_promise_unique is a compiler builtin.

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
    copy(Value::ui, Copy::uo),
    [will_not_call_mercury, thread_safe, promise_pure, will_not_modify_trail,
        does_not_affect_liveness],
"
    MR_save_transient_registers();
    Copy = MR_deep_copy(Value, (MR_TypeInfo) TypeInfo_for_T, NULL, NULL);
    MR_restore_transient_registers();
").

:- pragma foreign_proc("C",
    copy(Value::in, Copy::uo),
    [will_not_call_mercury, thread_safe, promise_pure, will_not_modify_trail,
        does_not_affect_liveness],
"
    MR_save_transient_registers();
    Copy = MR_deep_copy(Value, (MR_TypeInfo) TypeInfo_for_T, NULL, NULL);
    MR_restore_transient_registers();
").

:- pragma foreign_proc("C#",
    copy(X::ui, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = deep_copy(X);
").

:- pragma foreign_proc("C#",
    copy(X::in, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = deep_copy(X);
").

:- pragma foreign_proc("Java",
    copy(X::ui, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = deep_copy(X);
").

:- pragma foreign_proc("Java",
    copy(X::in, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = deep_copy(X);
").

:- pragma foreign_proc("Erlang",
    copy(X::ui, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = X
").

:- pragma foreign_proc("Erlang",
    copy(X::in, Y::uo),
    [may_call_mercury, thread_safe, promise_pure, terminates],
"
    Y = X
").

%-----------------------------------------------------------------------------%

%
% A definition of the Mercury type void/0 is needed because we can generate
% references to it in code.  See tests/hard_coded/nullary_ho_func.m for an
% example of code which does.
%
:- pragma foreign_decl("C#", "
namespace mercury.builtin {
    public class void_0
    {
        // Make the constructor private to ensure that we can
        // never create an instance of this class.
        private void_0()
        {
        }
    }
}
").
:- pragma foreign_code("Java", "
    public static class Void_0
    {
        // Make the constructor private to ensure that we can
        // never create an instance of this class.
        private Void_0()
        {
        }
    }
").

%-----------------------------------------------------------------------------%

:- pragma foreign_code("Java", "

    //
    // Definitions of builtin types
    //

    public static class Tuple_0
    {
        // stub only
    }

    public static class Func_0
    {
        // stub only
    }

    public static class C_pointer_0
    {
        // stub only
    }

    //
    // Generic unification/comparison routines
    //

    public static boolean
    unify_2_p_0 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        // stub only
        throw new java.lang.Error (""unify/3 not implemented"");
    }

    public static Comparison_result_0
    compare_3_p_0 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        // stub only
        throw new java.lang.Error (""compare/3 not implemented"");
    }

    public static Comparison_result_0
    compare_3_p_1 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        return compare_3_p_0(ti, x, y);
    }

    public static Comparison_result_0
    compare_3_p_2 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        return compare_3_p_0(ti, x, y);
    }

    public static Comparison_result_0
    compare_3_p_3 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        return compare_3_p_0(ti, x, y);
    }

    public static Comparison_result_0
    compare_representation_3_p_0 (mercury.runtime.TypeInfo_Struct ti,
        java.lang.Object x, java.lang.Object y)
    {
        // stub only
        throw new java.lang.Error (
            ""compare_representation_3_p_0/3 not implemented"");
    }

    //
    // Type-specific unification routines for builtin types
    //

    public static boolean
    __Unify____tuple_0_0(java.lang.Object[] x, java.lang.Object[] y)
    {
        // stub only
        throw new java.lang.Error (""unify/2 for tuple types not implemented"");
    }

    public static boolean
    __Unify____func_0_0(java.lang.Object[] x, java.lang.Object[] y)
    {
        // stub only
        throw new java.lang.Error (""unify/2 for tuple types not implemented"");
    }


    public static boolean
    __Unify____c_pointer_0_0(java.lang.Object x, java.lang.Object y)
    {
        // XXX should we try calling a Java comparison routine?
        throw new java.lang.Error (""unify/2 called for c_pointer type"");
    }

    public static boolean
    __Unify____void_0_0(mercury.builtin.Void_0 x, mercury.builtin.Void_0 y)
    {
        // there should never be any values of type void/0
        throw new java.lang.Error (""unify/2 called for void type"");
    }

    //
    // Type-specific comparison routines for builtin types
    //

    public static Comparison_result_0
    __Compare____tuple_0_0
        (mercury.builtin.Tuple_0 x, mercury.builtin.Tuple_0 y)
    {
        // stub only
        throw new java.lang.Error
            (""compare/3 for tuple types not implemented"");
    }

    public static Comparison_result_0
    __Compare____func_0_0(java.lang.Object[] x, java.lang.Object[] y)
    {
        // comparing values of higher-order types is a run-time error
        throw new java.lang.Error (""compare/3 called for func type"");
    }

    public static Comparison_result_0
    __Compare____c_pointer_0_0(java.lang.Object x, java.lang.Object y)
    {
        // XXX should we try calling a Java comparison routine?
        throw new java.lang.Error
            (""compare/3 called for c_pointer type"");
    }

    public static Comparison_result_0
    __Compare____void_0_0(mercury.builtin.Void_0 x, mercury.builtin.Void_0 y)
    {
        // there should never be any values of type void/0
        throw new java.lang.Error (""compare/3 called for void type"");
    }
").

%-----------------------------------------------------------------------------%
%
% semidet_succeed and semidet_fail
%

% semidet_succeed and semidet_fail are implemented using the foreign language
% interface to make sure that the compiler doesn't issue any determinism
% warnings for them.

:- pragma foreign_proc("C",
    semidet_succeed,
    [will_not_call_mercury, thread_safe, promise_pure,
        does_not_affect_liveness],
"
    SUCCESS_INDICATOR = MR_TRUE;
").
:- pragma foreign_proc("C",
    semidet_fail,
    [will_not_call_mercury, thread_safe, promise_pure,
        does_not_affect_liveness],
"
    SUCCESS_INDICATOR = MR_FALSE;
").

:- pragma foreign_proc("C#",
    semidet_succeed,
    [will_not_call_mercury, thread_safe, promise_pure],
"
    SUCCESS_INDICATOR = true;
").
:- pragma foreign_proc("C#",
    semidet_fail,
    [will_not_call_mercury, thread_safe, promise_pure],
"
    SUCCESS_INDICATOR = false;
").

:- pragma foreign_proc("Erlang",
    semidet_succeed,
    [will_not_call_mercury, thread_safe, promise_pure],
"
    SUCCESS_INDICATOR = true
").
:- pragma foreign_proc("Erlang",
    semidet_fail,
    [will_not_call_mercury, thread_safe, promise_pure],
"
    SUCCESS_INDICATOR = false
").

% We can't just use "true" and "fail" here, because that provokes warnings
% from determinism analysis, and the library is compiled with --halt-at-warn.
% So instead we use 0+0 = (or \=) 0.
% This is guaranteed to succeed or fail (respectively),
% and with a bit of luck will even get optimized by constant propagation.
% But this optimization won't happen until after determinism analysis,
% which doesn't know anything about integer arithmetic,
% so this code won't provide a warning from determinism analysis.

semidet_succeed :-
    0 + 0 = 0.
semidet_fail :-
    0 + 0 \= 0.

semidet_true :-
    semidet_succeed.
semidet_false :-
    semidet_fail.

%-----------------------------------------------------------------------------%
%
% cc_multi_equal
%

% NOTE: cc_multi_equal/2 is handled specially in browser/declarative_tree.m.
% Any changes here may need to be reflected there.

:- pragma foreign_proc("C",
    cc_multi_equal(X::in, Y::out),
    [will_not_call_mercury, thread_safe, promise_pure,
        does_not_affect_liveness],
"
    Y = X;
").
:- pragma foreign_proc("C",
    cc_multi_equal(X::di, Y::uo),
    [will_not_call_mercury, thread_safe, promise_pure,
        does_not_affect_liveness],
"
    Y = X;
").

:- pragma foreign_proc("C#",
    cc_multi_equal(X::in, Y::out),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X;
").
:- pragma foreign_proc("C#",
    cc_multi_equal(X::di, Y::uo),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X;
").

:- pragma foreign_proc("Java",
    cc_multi_equal(X::in, Y::out),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X;
").
:- pragma foreign_proc("Java",
    cc_multi_equal(X::di, Y::uo),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X;
").

:- pragma foreign_proc("Erlang",
    cc_multi_equal(X::in, Y::out),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X
").
:- pragma foreign_proc("Erlang",
    cc_multi_equal(X::di, Y::uo),
    [will_not_call_mercury, thread_safe, promise_pure],
"
    Y = X
").

:- pragma promise_pure(cc_multi_equal/2).

cc_multi_equal(X, X).

%-----------------------------------------------------------------------------%

impure_true :-
    impure private_builtin.imp.

semipure_true :-
    semipure private_builtin.semip.

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
    unsafe_cast_any_to_ground(X::ia) = (Y::out),
    [promise_pure, will_not_call_mercury, thread_safe, will_not_modify_trail],
"
    Y = X;
").

:- pragma foreign_proc("C#",
    unsafe_cast_any_to_ground(X::ia) = (Y::out),
    [promise_pure, will_not_call_mercury, thread_safe, will_not_modify_trail],
"
    Y = X;
").

:- pragma foreign_proc("Java",
    unsafe_cast_any_to_ground(X::ia) = (Y::out),
    [promise_pure, will_not_call_mercury, thread_safe, will_not_modify_trail],
"
    Y = X;
").

:- pragma foreign_proc("Erlang",
    unsafe_cast_any_to_ground(X::ia) = (Y::out),
    [promise_pure, will_not_call_mercury, thread_safe, will_not_modify_trail],
"
    Y = X
").

%-----------------------------------------------------------------------------%
:- end_module builtin.
%-----------------------------------------------------------------------------%
