%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2006 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: stream.m.
% Authors: juliensf, maclarty.
%
% This module provides a family of typeclasses for defining streams in Mercury.
% It also provides some generic predicates that operate on instances of these
% typeclasses.
%
% TODO:
% * Add non-blocking versions of the stream operations.
% * Thread-safety aspects(?)
% * Add a typeclass to hold the offset method for binary input streams.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module stream.
:- interface.

:- import_module bool.
:- import_module string.

%-----------------------------------------------------------------------------%
%
% Stream errors
%

:- type stream.name == string.

:- type stream.result(T, Error)
    --->    ok(T)
    ;       eof
    ;       error(Error).

:- typeclass stream.error(Error) where
[

    % Convert a stream error into a human-readable format.
    % e.g. for use in error messages.
    %
    func error_message(Error) = string
].

%-----------------------------------------------------------------------------%
%
% Streams
%

    % A stream consists of a handle type and a state type.
    % The state type is threaded through, and destructively updated by,
    % the stream operations.
    %
:- typeclass stream.stream(Stream, State) <= (Stream -> State) where
[ 
        % Returns a descriptive name for the stream.
        % Intended for use in error messages.
        %
        pred name(Stream::in, stream.name::out, State::di, State::uo) is det
].

%-----------------------------------------------------------------------------%
%
% Input streams
%

    % An input stream is a source of data.
    %
:- typeclass stream.input(Stream, State, Error)
    <= ( stream(Stream, State), stream.error(Error), (Stream -> Error) ) where
[
    % For buffered input streams this method causes the buffer to be filled.
    % For unbuffered streams it is a no-op.
    %
    pred fill(Stream::in, State::di, State::uo) is det
].

    % A reader stream is a subclass of specific input stream that can be
    % used to read data of a specific type from the input stream.  
    % A single input streams can support multiple reader subclasses.
    % 
:- typeclass stream.reader(Stream, Unit, State, Error)
    <= stream.input(Stream, State, Error) where
[
    % Get the next unit from the given stream.  The get operation should
    % block until the next unit is available.
    %
    pred get(Stream::in, stream.result(Unit, Error)::out, State::di, State::uo)
        is det
].

%-----------------------------------------------------------------------------%
%
% Output streams
%
   
    % An output stream is a destination for data.
    % Note that unlike input streams, output stream do not have an explicit
    % error type.  They should handle errors by throwing an exception.
    %
:- typeclass stream.output(Stream, State)
    <= stream(Stream, State) where
[
    % For buffered output streams completely write out any data in the
    % buffer.  For unbuffered streams this operation is a no-op.
    %
    pred flush(Stream::in, State::di, State::uo) is det
].

    % A writer stream is a subclass of specific output stream that can be
    % used to write data of a specific type to the output stream.  
    % A single output stream can support multiple writer subclasses.
    %
:- typeclass stream.writer(Stream, Unit, State)
    <= stream.output(Stream, State) where
[
    % Write the next unit to the given stream.
    % The put operation should block until the unit is completely written.
    %
    pred put(Stream::in, Unit::in, State::di, State::uo) is det
].

%-----------------------------------------------------------------------------%
%
% Duplex streams
%

    % A duplex stream is a stream that can act as both a source and
    % destination of data, i.e. it is a both an input and an output stream.
    %
:- typeclass stream.duplex(Stream, State, Error)
    <= ( stream.input(Stream, State, Error), stream.output(Stream, State))
        where [].

%----------------------------------------------------------------------------%
%
% Putback streams
%

    % A putback stream is an input stream that allows data to be pushed back
    % onto the stream.  As with reader subclasses it is possible to define
    % multiple putback streams for a single input stream.
    %
:- typeclass stream.putback(Stream, Unit, State, Error)
    <= stream.reader(Stream, Unit, State, Error) where
[
    % Un-gets a unit from the specified input stream.
    % At least one unit of can be placed back on the stream.
    %
    pred unget(Stream::in, Unit::in, State::di, State::uo) is det
]. 
   
    % As above but guarantees that an unlimited number of units may
    % be pushed back onto the stream.
    %
:- typeclass stream.unbounded_putback(Stream, Unit, State, Error)
    <= stream.putback(Stream, Unit, State, Error) where [].

%----------------------------------------------------------------------------%
%
% Seekable streams
%

    % stream.whence denotes the base for a seek operation.
    %   set - seek relative to the start of the file
    %   cur - seek relative to the current position in the file
    %   end - seek relative to the end of the file.
    %
:- type stream.whence
    --->    set
    ;       cur
    ;       end.

:- typeclass stream.seekable(Stream, State) <= stream(Stream, State)
    where
[
    % Seek to an offset relative to whence on the specified stream.
    % The offset is measured in bytes.
    %
    pred seek(Stream::in, stream.whence::in, int::in, State::di, State::uo)
        is det
].

%----------------------------------------------------------------------------%
%
% Line oriented streams
%

    % A line oriented stream is a stream that keeps track of line numbers.
    %
:- typeclass stream.line_oriented(Stream, State) <= stream(Stream, State)
    where
[
    % Get the current line number for the specified stream.
    %
    pred get_line(Stream::in, int::out, State::di, State::uo) is det,
    
    % Set the current line number of the specified stream.
    %
    pred set_line(Stream::in, int::in,  State::di, State::uo) is det
].

%-----------------------------------------------------------------------------%
%
% Generic folds over input streams
%

:- type stream.res(Error)
    --->    ok
    ;       error(Error).

    % stream.maybe_partial_res is used when it is possible to return
    % a partial result when an error occurs.
    %
:- type stream.maybe_partial_res(T, Error)
    --->    ok(T)
    ;       error(T, Error).

    % Applies the given closure to each Unit read from the input stream
    % in turn, until eof or error.
    %
:- pred stream.input_stream_fold(Stream, pred(Unit, T, T), T,
    stream.maybe_partial_res(T, Error), State, State)
    <= stream.reader(Stream, Unit, State, Error).
:- mode stream.input_stream_fold(in, in(pred(in, in, out) is det),
    in, out, di, uo) is det.
:- mode stream.input_stream_fold(in, in(pred(in, in, out) is cc_multi),
    in, out, di, uo) is cc_multi.

    % Applies the given closure to each Unit read from the input stream
    % in turn, until eof or error.
    %
:- pred stream.input_stream_fold_state(Stream, pred(Unit, State, State),
    stream.res(Error), State, State)
    <= stream.reader(Stream, Unit, State, Error).
:- mode stream.input_stream_fold_state(in, in(pred(in, di, uo) is det),
    out, di, uo) is det.
:- mode stream.input_stream_fold_state(in, in(pred(in, di, uo) is cc_multi),
    out, di, uo) is cc_multi.
    
    % Applies the given closure to each Unit read from the input stream
    % in turn, until eof or error.
    %
:- pred stream.input_stream_fold2_state(Stream,
    pred(Unit, T, T, State, State), T, stream.maybe_partial_res(T, Error),
    State, State) <= stream.reader(Stream, Unit, State, Error).
:- mode stream.input_stream_fold2_state(in,
    in(pred(in, in, out, di, uo) is det),
    in, out, di, uo) is det.
:- mode stream.input_stream_fold2_state(in,
    in(pred(in, in, out, di, uo) is cc_multi),
    in, out, di, uo) is cc_multi.

    % Applies the given closure to each Unit read from the input stream
    % in turn, until eof or error, or the closure returns `no' as its
    % second argument.
    %
:- pred stream.input_stream_fold2_state_maybe_stop(Stream,
    pred(Unit, bool, T, T, State, State),
    T, stream.maybe_partial_res(T, Error), State, State)
    <= stream.reader(Stream, Unit, State, Error).
:- mode stream.input_stream_fold2_state_maybe_stop(in,
    in(pred(in, out, in, out, di, uo) is det), in, out, di, uo) is det.
:- mode stream.input_stream_fold2_state_maybe_stop(in,
    in(pred(in, out, in, out, di, uo) is cc_multi), in, out, di, uo)
    is cc_multi.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

%-----------------------------------------------------------------------------%
%
% Folds over input streams
%

stream.input_stream_fold(Stream, Pred, T0, Res, !S) :-
    get(Stream, Result, !S),
    (
        Result = ok(Unit),
        Pred(Unit, T0, T1),
        stream.input_stream_fold(Stream, Pred, T1, Res, !S)
    ;
        Result = eof,
        Res = ok(T0)
    ;
        Result = error(Error),
        Res = error(T0, Error)
    ).

stream.input_stream_fold_state(Stream, Pred, Res, !S) :-
    get(Stream, Result0, !S),
    (
        Result0 = ok(Result),
        Pred(Result, !S),
        stream.input_stream_fold_state(Stream, Pred, Res, !S)
    ;
        Result0 = eof,
        Res = ok
    ;
        Result0 = error(Error),
        Res = error(Error)
    ).

stream.input_stream_fold2_state(Stream, Pred, T0, Res, !S) :-
    get(Stream, Result0, !S),
    (
        Result0 = ok(Result),
        Pred(Result, T0, T1, !S),
        stream.input_stream_fold2_state(Stream, Pred, T1, Res, !S)
    ;
        Result0 = eof,
        Res = ok(T0)
    ;
        Result0 = error(Error),
        Res = error(T0, Error)
    ).

stream.input_stream_fold2_state_maybe_stop(Stream, Pred, T0, Res, !S) :-
    get(Stream, Result0, !S),
    (
        Result0 = ok(Result),
        Pred(Result, Continue, T0, T1, !S),
        (
            Continue = no,
            Res = ok(T1)
        ;
            Continue = yes,
            stream.input_stream_fold2_state_maybe_stop(Stream, Pred, T1, Res,
                !S)
        )
    ;
        Result0 = eof,
        Res = ok(T0)
    ;
        Result0 = error(Error),
        Res = error(T0, Error)
    ).

%-----------------------------------------------------------------------------%
:- end_module stream.
%-----------------------------------------------------------------------------%
