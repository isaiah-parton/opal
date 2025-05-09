package sdl3app

import ".."
import kn "../../katana"
import "../../katana/sdl3glue"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "vendor:sdl3"

detect_tiling_window_manager :: proc() -> bool {
	if ODIN_OS == .Linux {
		if value, ok := os.lookup_env("XDG_CURRENT_DESKTOP"); ok {
			if strings.contains(value, "i3") ||
			   strings.contains(value, "bspwm") ||
			   strings.contains(value, "sway") {
				return true
			}
			delete(value)
		}
	}
	return false
}

state: rawptr

App_Callback :: #type proc(app: ^App)

App :: struct {
	run:      bool,
	cursors:  [sdl3.SystemCursor]^sdl3.Cursor,
	window:   ^sdl3.Window,
	platform: kn.Platform,
	on_start: App_Callback,
	on_frame: App_Callback,
	on_stop:  App_Callback,
}

translate_keycode :: proc(code: sdl3.Keycode) -> opal.Keyboard_Key {
	switch code {
	case sdl3.K_LEFT:
		return .Left
	case sdl3.K_RIGHT:
		return .Right
	case sdl3.K_LSHIFT:
		return .Left_Shift
	case sdl3.K_RSHIFT:
		return .Right_Shift
	case sdl3.K_LCTRL:
		return .Left_Control
	case sdl3.K_RCTRL:
		return .Right_Control
	case sdl3.K_BACKSPACE:
		return .Backspace
	case sdl3.K_DELETE:
		return .Delete
	case sdl3.K_F3:
		return .F3
	}
	return .Escape
}

hit_test_callback :: proc "c" (
	window: ^sdl3.Window,
	point: ^sdl3.Point,
	data: rawptr,
) -> sdl3.HitTestResult {
	context = runtime.default_context()
	width, height: i32
	sdl3.GetWindowSize(window, &width, &height)
	titlebar := sdl3.Rect{0, 0, width, 30}
	opal.handle_mouse_motion(f32(point.x), f32(point.y))
	CORNER_SIZE :: 8
	if sdl3.PointInRect(point^, {0, 0, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_TOPLEFT
	}
	if sdl3.PointInRect(point^, {width - CORNER_SIZE, 0, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_TOPRIGHT
	}
	if sdl3.PointInRect(point^, {0, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_BOTTOMLEFT
	}
	if sdl3.PointInRect(
		point^,
		{width - CORNER_SIZE, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE},
	) {
		return .RESIZE_BOTTOMRIGHT
	}
	SIZE :: 3
	if sdl3.PointInRect(point^, {0, 0, SIZE, height}) {
		return .RESIZE_LEFT
	}
	if sdl3.PointInRect(point^, {width - SIZE, 0, SIZE, height}) {
		return .RESIZE_RIGHT
	}
	if sdl3.PointInRect(point^, {0, 0, width, SIZE}) {
		return .RESIZE_TOP
	}
	if sdl3.PointInRect(point^, {0, height - SIZE, width, SIZE}) {
		return .RESIZE_BOTTOM
	}
	if !opal.global_ctx.widget_hovered && sdl3.PointInRect(point^, titlebar) {
		return .DRAGGABLE
	}
	return .NORMAL
}

app_main :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = runtime.default_context()
	assert(state != nil, "You must initialize `state` before running your app")
	appstate^ = state
	app := (^App)(appstate^)

	app.window = sdl3.CreateWindow("OPAL", 800, 600, {.RESIZABLE, .BORDERLESS, .TRANSPARENT})
	sdl3.SetWindowHitTest(app.window, hit_test_callback, nil)
	sdl3.SetWindowMinimumSize(app.window, 500, 400)
	if !sdl3.StartTextInput(app.window) {
		panic("Can't accept text input!")
	}

	platform := sdl3glue.make_platform_sdl3glue(app.window)
	kn.start_on_platform(platform)
	opal.init()
	opal.global_ctx.callback_data = app
	opal.global_ctx.on_set_cursor = proc(cursor: opal.Cursor, data: rawptr) -> bool {
		app := (^App)(data)
		switch cursor {
		case .Normal:
			return sdl3.SetCursor(app.cursors[.DEFAULT])
		case .Pointer:
			return sdl3.SetCursor(app.cursors[.POINTER])
		case .Text:
			return sdl3.SetCursor(app.cursors[.TEXT])
		}
		return false
	}

	// Create system cursors
	for cursor in sdl3.SystemCursor {
		app.cursors[cursor] = sdl3.CreateSystemCursor(cursor)
	}

	assert(app.on_start != nil, "No `on_start` procedure defined!")
	app.on_start(app)

	return .CONTINUE
}

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	using opal
	context = runtime.default_context()
	app := (^App)(appstate)
	ctx := global_ctx

	kn.new_frame()

	assert(app.on_frame != nil, "No `on_frame` procedure defined!")
	app.on_frame(app)

	kn.set_clear_color({})
	if requires_redraw() {
		kn.present()
	}

	free_all(context.temp_allocator)

	// Determine refresh rate
	display_id := sdl3.GetDisplayForWindow(app.window)
	display_mode := sdl3.GetCurrentDisplayMode(display_id)

	// TODO: Add a setter proc to opal
	ctx.frame_interval = time.Duration(f32(time.Second) / display_mode.refresh_rate)

	if !app.run {
		return .SUCCESS
	}
	return .CONTINUE
}

app_event :: proc "c" (appstate: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
	using opal
	context = runtime.default_context()
	app := (^App)(appstate)
	#partial switch event.type {
	case .QUIT:
		app.run = false
	case .KEY_DOWN:
		key := translate_keycode(event.key.key)
		if event.key.repeat {
			handle_key_repeat(key)
		}
		handle_key_down(key)
	case .KEY_UP:
		handle_key_up(translate_keycode(event.key.key))
	case .MOUSE_BUTTON_DOWN:
		handle_mouse_down(Mouse_Button(int(event.button.button) - 1))
	case .MOUSE_BUTTON_UP:
		handle_mouse_up(Mouse_Button(int(event.button.button) - 1))
	case .MOUSE_MOTION:
		handle_mouse_motion(event.motion.x, event.motion.y)
	case .MOUSE_WHEEL:
		handle_mouse_scroll(event.wheel.x, event.wheel.y)
	case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
		handle_window_size_change(event.window.data1, event.window.data2)
	case .WINDOW_RESTORED:
		draw_frames(2)
	case .TEXT_INPUT:
		handle_text_input(event.text.text)
	}
	return .CONTINUE
}

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = runtime.default_context()
	app := (^App)(appstate)
	if app.on_stop != nil {
		app.on_stop(app)
	}
	// kn.destroy_platform(&app.platform)
	kn.shutdown()
	opal.deinit()
	sdl3.DestroyWindow(app.window)
	sdl3.Quit()
}

run :: proc() {
	sdl3.EnterAppMainCallbacks(0, nil, app_main, app_iter, app_event, app_quit)
}
