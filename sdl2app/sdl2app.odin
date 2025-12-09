package sdl2app

import ".."
import kn "../../katana"
import "../../katana/sdl2glue"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import "vendor:sdl2"

state: rawptr

App_Callback :: #type proc(app: ^App)

App :: struct {
	using descriptor:   App_Descriptor,
	run:                bool,
	cursors:            [sdl2.SystemCursor]^sdl2.Cursor,
	window:             ^sdl2.Window,
	platform:           kn.Platform,
	window_grab_box:    opal.Box,
	enable_window_grab: bool,
	on_start:           App_Callback,
	on_frame:           App_Callback,
	on_stop:            App_Callback,
}

App_Descriptor :: struct {
	width:              i32,
	height:             i32,
	min_width:          i32,
	min_height:         i32,
	radius:             f32,
	customize_window:   bool,
	vsync:              bool,
	min_frame_interval: time.Duration,
}

@(private)
global_descriptor: ^App_Descriptor

translate_keycode :: proc(keysm: sdl2.Keysym) -> opal.Keyboard_Key {
	#partial switch keysm.scancode {
	case .LEFT:
		return .Left
	case .RIGHT:
		return .Right
	case .LSHIFT:
		return .Left_Shift
	case .RSHIFT:
		return .Right_Shift
	case .LCTRL:
		return .Left_Control
	case .RCTRL:
		return .Right_Control
	case .BACKSPACE:
		return .Backspace
	case .DELETE:
		return .Delete
	case .RETURN:
		return .Enter
	case .F1 ..= .F12:
		return opal.Keyboard_Key(int(opal.Keyboard_Key.F1) + int(keysm.scancode - .F1))
	case .A ..= .Z:
		return opal.Keyboard_Key(int(opal.Keyboard_Key.A) + int(keysm.scancode - .A))
	case .NUM0 ..= .NUM9:
		return opal.Keyboard_Key(int(opal.Keyboard_Key.Zero) + int(keysm.scancode - .NUM0))
	}
	return .Escape
}

hit_test_callback :: proc "c" (
	window: ^sdl2.Window,
	point: ^sdl2.Point,
	data: rawptr,
) -> sdl2.HitTestResult {
	context = runtime.default_context()
	app := (^App)(data)

	width, height: i32
	sdl2.GetWindowSize(window, &width, &height)
	titlebar := sdl2.Rect {
		i32(app.window_grab_box.lo.x),
		i32(app.window_grab_box.lo.y),
		i32(app.window_grab_box.hi.x - app.window_grab_box.lo.x),
		i32(app.window_grab_box.hi.y - app.window_grab_box.lo.y),
	}

	opal.handle_mouse_motion(f32(point.x), f32(point.y))

	CORNER_SIZE :: 8
	if sdl2.PointInRect(point, &{0, 0, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_TOPLEFT
	}
	if sdl2.PointInRect(point, &{width - CORNER_SIZE, 0, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_TOPRIGHT
	}
	if sdl2.PointInRect(point, &{0, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE}) {
		return .RESIZE_BOTTOMLEFT
	}
	if sdl2.PointInRect(
		point,
		&{width - CORNER_SIZE, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE},
	) {
		return .RESIZE_BOTTOMRIGHT
	}
	SIZE :: 4
	if sdl2.PointInRect(point, &{0, 0, SIZE, height}) {
		return .RESIZE_LEFT
	}
	if sdl2.PointInRect(point, &{width - SIZE, 0, SIZE, height}) {
		return .RESIZE_RIGHT
	}
	if sdl2.PointInRect(point, &{0, 0, width, SIZE}) {
		return .RESIZE_TOP
	}
	if sdl2.PointInRect(point, &{0, height - SIZE, width, SIZE}) {
		return .RESIZE_BOTTOM
	}
	if app.enable_window_grab && sdl2.PointInRect(point, &titlebar) {
		return .DRAGGABLE
	}
	return .NORMAL
}

app_main :: proc "c" (appstate: rawptr, argc: i32, argv: [^]cstring) {
	context = runtime.default_context()
	assert(state != nil, "You must initialize `state` before running your app")
	app := (^App)(appstate)

	if global_descriptor != nil {
		app.descriptor = global_descriptor^
	} else {
		app.descriptor = {
			width      = 800,
			height     = 600,
			min_width  = 500,
			min_height = 500,
		}
	}

	window_flags := sdl2.WindowFlags{.RESIZABLE}
	if app.customize_window {
		window_flags += {.BORDERLESS}
	}

	app.window = sdl2.CreateWindow("OPAL", -1, -1, app.width, app.height, window_flags)

	// Hit test callback for modified moving/resizing hitboxes
	if app.customize_window {
		sdl2.SetWindowHitTest(app.window, hit_test_callback, app)
	}
	sdl2.SetWindowMinimumSize(app.window, app.min_width, app.min_height)

	sdl2.StartTextInput()

	platform := sdl2glue.make_platform_sdl2glue(app.window)
	kn.start_on_platform(platform)

	opal.init({
		callback_data = app,
		on_set_cursor = proc(cursor: opal.Cursor, data: rawptr) -> bool {
			app := (^App)(data)
			switch cursor {
			case .Normal:
				sdl2.SetCursor(app.cursors[.ARROW])
			case .Pointer:
				sdl2.SetCursor(app.cursors[.HAND])
			case .Text:
				sdl2.SetCursor(app.cursors[.IBEAM])
			case .Move:
				sdl2.SetCursor(app.cursors[.SIZEALL])
			case .Resize_EW:
				sdl2.SetCursor(app.cursors[.SIZEWE])
			case .Resize_NS:
				sdl2.SetCursor(app.cursors[.SIZENS])
			case .Resize_NWSE:
				sdl2.SetCursor(app.cursors[.SIZENWSE])
			case .Resize_NESW:
				sdl2.SetCursor(app.cursors[.SIZENESW])
			}
			return true
		},
		on_set_clipboard = proc(_: rawptr, text: string) -> bool {
			text_cstring := strings.clone_to_cstring(text)
			ok := sdl2.SetClipboardText(text_cstring)
			delete(text_cstring)
			return bool(ok)
		},
		on_get_clipboard = proc(_: rawptr) -> (text: string, ok: bool) {
			raw_text := sdl2.GetClipboardText()
			if raw_text == nil {
				return "", false
			}
			return string(cstring(raw_text)), true
		},
		on_get_screen_size = proc(data: rawptr) -> [2]f32 {
			app := (^App)(data)
			width, height: i32
			sdl2.GetWindowSize(app.window, &width, &height)
			return {f32(width), f32(height)}
		},
	})

	// Create system cursors
	for cursor in sdl2.SystemCursor {
		app.cursors[cursor] = sdl2.CreateSystemCursor(cursor)
	}

	assert(app.on_start != nil, "No `on_start` procedure defined!")
	app.on_start(app)

}

app_iter :: proc "c" (appstate: rawptr) {
	using opal
	context = runtime.default_context()
	app := (^App)(appstate)
	ctx := global_ctx

	kn.new_frame()

	assert(app.on_frame != nil, "No `on_frame` procedure defined!")
	app.on_frame(app)

	kn.set_clear_color({})
	if is_frame_active() {
		kn.present()
	}

	free_all(context.temp_allocator)

	// Determine refresh rate
	// display_id := sdl2.GetDisplayForWindow(app.window)
	// display_mode := sdl2.GetCurrentDisplayMode(display_id)

	// TODO: Add a setter proc to opal
	if app.vsync {
		ctx.frame_interval = 0
	} else {
		ctx.frame_interval = max(time.Duration(f32(time.Second) / 60), app.min_frame_interval)
	}
}

app_event :: proc "c" (appstate: rawptr, event: ^sdl2.Event) {
	using opal
	context = runtime.default_context()
	app := (^App)(appstate)
	#partial switch event.type {
	case .QUIT:
		app.run = false
	case .KEYDOWN:
		key := translate_keycode(event.key.keysym)
		if event.key.repeat != 0 {
			handle_key_repeat(key)
		}
		handle_key_down(key)
	case .KEYUP:
		handle_key_up(translate_keycode(event.key.keysym))
	case .MOUSEBUTTONDOWN:
		handle_mouse_down(Mouse_Button(int(event.button.button) - 1))
	case .MOUSEBUTTONUP:
		handle_mouse_up(Mouse_Button(int(event.button.button) - 1))
	case .MOUSEMOTION:
		handle_mouse_motion(f32(event.motion.x), f32(event.motion.y))
	case .MOUSEWHEEL:
		handle_mouse_scroll(f32(event.wheel.x), f32(event.wheel.y))
	case .TEXTINPUT:
		handle_text_input(transmute(cstring)&event.text.text)
	case .WINDOWEVENT:
		#partial switch event.window.event {
		case .RESIZED, .SIZE_CHANGED:
			handle_window_resize(event.window.data1, event.window.data2)
		case .RESTORED:
			draw_frames(2)

		case .MOVED:
			handle_window_move()
		case .FOCUS_LOST:
			handle_window_lost_focus()
		case .FOCUS_GAINED:
			handle_window_gained_focus()
		}
	}
}

app_quit :: proc "c" (appstate: rawptr) {
	context = runtime.default_context()
	app := (^App)(appstate)
	if app.on_stop != nil {
		app.on_stop(app)
	}
	// kn.destroy_platform(&app.platform)
	kn.shutdown()
	opal.deinit()
	sdl2.DestroyWindow(app.window)
	sdl2.Quit()
}

run :: proc(descriptor: ^App_Descriptor = nil) {
	global_descriptor = descriptor
	app := (^App)(state)
	app_main(state, 0, nil)
	for app.run {
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			app_event(state, &event)
		}
		app_iter(state)
	}
	app_quit(state)
}

app_use_node_for_window_grabbing :: proc(self: ^App, node: ^opal.Node) {
	self.enable_window_grab = node.is_hovered
	self.window_grab_box = node.box
}

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

