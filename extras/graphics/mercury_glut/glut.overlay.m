%-----------------------------------------------------------------------------%
% Copyright (C) 2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% file: glut.overlay.m
% author: juliensf
%
% This module provides an interface to the GLUT overlay API.
%
%-----------------------------------------------------------------------------%

:- module glut.overlay.

:- interface.

:- import_module glut.window.

:- import_module bool, std_util.

%-----------------------------------------------------------------------------%

:- type layer ---> normal ; overlay.

	% Returns `yes' of it is possible to establish an overlay for the
	% current window; `no' otherwise.
	%
:- pred overlay.possible(bool::out, io::di, io::uo) is det.

	% Establish an overlay for the current window.  Returns `ok'
	% if an overlay was established or error otherwise.  
	% 
:- pred overlay.establish(maybe_error::out, io::di, io::uo) is det.

	% Establish an overlay for the current window.
	% Aborts program if an overlay cannot be established.
	%
:- pred overlay.unsafe_establish(io::di, io::uo) is det.

	% Remove the overlay from the current window.  If the current
	% window does not have an overlay then this does nothing.
	%
:- pred overlay.remove(io::di, io::uo) is det.

	% Mark the overlay of the current window as needing to be 
	% redisplayed.
	% 
:- pred overlay.post_redisplay(io::di, io::uo) is det.

	% Mark the overlay of the specified window as needing to be
	% redisplayed.
	%
:- pred overlay.post_redisplay(window::in, io::di, io::uo) is det.

	% Change the layer in use for the current window.
	%
:- pred overlay.use_layer(layer::in, maybe_error::out, io::di, io::uo) is det.

	% Return the layer in use for the current window.
	%
:- pred overlay.layer_in_use(layer::out, io::di, io::uo) is det.

	% Shows the overlay for the current window.
	%
:- pred overlay.show(io::di, io::uo) is det.

	% Hides the overlay for the current window.
	%
:- pred overlay.hide(io::di, io::uo) is det.

	% Returns `yes' if the normal plane of the current window
	% has been damaged since the last display callback.
	% 
:- pred overlay.normal_damaged(bool::out, io::di, io::uo) is det.

	% Returns `no' if the current window has no overlay.
	% Otherwise returns `yes(IsDamaged)' where `IsDamaged'
	% is the status of the current window's overlay since the
	% last display callback.
	%
:- pred overlay.overlay_damaged(maybe(bool)::out, io::di, io::uo) is det.

	% Returns `no' if the current window has no overlay.
	% Otherwise returns `yes(Index)' where `Index' is the 
	% transparent color index for the overlay of the current window.
	%
:- pred overlay.transparent_index(maybe(int)::out, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- pragma foreign_decl("C", "#include <GL/glut.h>").

:- pragma foreign_import_module("C", bool).

%-----------------------------------------------------------------------------%

:- func glut_normal = int.
:- pragma foreign_proc("C",
	glut_normal = (Value::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Value = (MR_Integer) GLUT_NORMAL;
").

:- func glut_overlay = int.
:- pragma foreign_proc("C",
	glut_overlay = (Value::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Value = (MR_Integer) GLUT_OVERLAY;
").

:- func layer_to_int(layer) = int.

layer_to_int(normal) = glut_normal.
layer_to_int(overlay) = glut_overlay.

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.possible(Result::out, IO0::di, IO::uo),
	[may_call_mercury, promise_pure, terminates],
"
	if (glutLayerGet(GLUT_OVERLAY_POSSIBLE)) {
		Result = ML_bool_return_yes();
	} else {
		Result = ML_bool_return_no();
	}
	IO = IO0;
").

%-----------------------------------------------------------------------------%

overlay.establish(Result, !IO) :-
	overlay.establish_2(Result0, !IO),
	Result = ( Result0 = 1 -> ok ; error("Unable to establish overlay.") ).

:- pred overlay.establish_2(int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
	overlay.establish_2(Result::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	if (glutLayerGet(GLUT_OVERLAY_POSSIBLE)) {
		glutEstablishOverlay();
		Result = 1;
	} else {
		Result = 0;
	}
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.unsafe_establish(IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutEstablishOverlay();
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.remove(IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutRemoveOverlay();
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.post_redisplay(IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutPostOverlayRedisplay();
	IO = IO0;
").
	
:- pragma foreign_proc("C",
	overlay.post_redisplay(Window::in, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutPostWindowOverlayRedisplay((int) Window);
	IO = IO0;
").
	
%-----------------------------------------------------------------------------%

overlay.use_layer(Layer, Result, !IO) :-
	overlay.use_layer_2(layer_to_int(Layer), Result0, !IO),
	( Result0 = 1 -> Result = ok
	; Result0 = 0 -> Result = error("Unable to change layer.")
	; error("Unknown result from layer change.")
	).

:- pred overlay.use_layer_2(int::in, int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
	overlay.use_layer_2(Layer::in, Result::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	if ((GLenum) Layer == GLUT_NORMAL) {
		glutUseLayer(GLUT_NORMAL);
		Result = 1;
	} else {
		if (glutLayerGet(GLUT_HAS_OVERLAY)) {
			glutUseLayer(GLUT_OVERLAY);
			Result = 1;
		} else {
			Result = 0;
		}
	}
	IO = IO0;
").

%-----------------------------------------------------------------------------%

overlay.layer_in_use(Layer, !IO) :-
	overlay.layer_in_use_2(Layer0, !IO),
	( Layer0 = glut_normal -> Layer = normal
	; Layer0 = glut_overlay -> Layer = overlay
	; error("Unable to determine which layer is in use.")
	).

:- pred overlay.layer_in_use_2(int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
	overlay.layer_in_use_2(Layer::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	Layer = (MR_Integer) glutLayerGet(GLUT_LAYER_IN_USE);
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.show(IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutShowOverlay();
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.hide(IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	glutHideOverlay();
	IO = IO0;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	overlay.normal_damaged(Result::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	if (glutLayerGet(GLUT_NORMAL_DAMAGED)) {
		Result = ML_bool_return_yes();
	} else {
		Result = ML_bool_return_no();
	}
	IO = IO0;
").

overlay.overlay_damaged(Result, !IO) :-
	overlay.overlay_damaged_2(Result0, !IO),
	( Result0 = 0 -> Result = no
	; Result0 = 1 -> Result = yes(no)
	; Result0 = 2 -> Result = yes(yes)
	; error("Uknown value returned from overlay.overlay_damaged_2/3.")
	).

	% Returns `0' if there is no overlay
	%         `1' if the overlay is undamaged
	%         `2' if the overlay is damaged
	%
:- pred overlay.overlay_damaged_2(int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
	overlay.overlay_damaged_2(Result::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	MR_Integer r;

	r = glutLayerGet(GLUT_OVERLAY_DAMAGED);

	if (r == -1) {
		Result = 0;
	} else if (r == 0) {
		Result = 1;
	} else {
		Result = 2;
	}
	IO = IO0;
").

%-----------------------------------------------------------------------------%

overlay.transparent_index(MaybeIndex, !IO) :-
	overlay.transparent_index_2(Result, !IO),
	( Result = -1 -> MaybeIndex = no
	; Result >= 0 -> MaybeIndex = yes(Result)
	; error("Unknown value returned from overlay.tranparent_index_2/3.")
	).

:- pred overlay.transparent_index_2(int::out, io::di, io::uo) is det.
:- pragma foreign_proc("C",
	overlay.transparent_index_2(Index::out, IO0::di, IO::uo),
	[will_not_call_mercury, promise_pure],
"
	Index = (MR_Integer) glutLayerGet(GLUT_TRANSPARENT_INDEX);
	IO = IO0;
").

%-----------------------------------------------------------------------------%
:- end_module glut.overlay.
%-----------------------------------------------------------------------------%