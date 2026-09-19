package opal

import "core:math"

add_spinner :: proc(center: [2]f32, radius: f32, color: Color) {
	from := f32(get_run_time() * 2) * math.PI
	to := from + 2.5 + math.sin(f32(get_run_time() * 3)) * 1

	width := radius * 0.25

	add_arc(center, from, to, radius - width, radius, paint = color)
}

add_arrow :: proc(pos: [2]f32, scale: f32, thickness: f32, angle: f32 = 0, paint: Paint_Variant) {
	push_matrix()
	translate(pos)
	rotate(angle)
	translate(-pos)
	add_lines(
		{
			pos + [2]f32{-0.5, -0.877} * scale,
			pos + [2]f32{0.5, 0} * scale,
			pos + [2]f32{-0.5, 0.877} * scale,
		},
		thickness,
		paint = paint,
	)
	pop_matrix()
}

add_check :: proc(pos: [2]f32, scale: f32, thickness: f32, color: Color) {
	add_lines(
		{pos + {-1, -0.047} * scale, pos + {-0.333, 0.619} * scale, pos + {1, -0.713} * scale},
		thickness,
		paint = color,
	)
}


add_box :: #force_inline proc(box: Box, radius: [4]f32, paint: Paint_Variant) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_box_proc != nil)
	adapter.add_box_proc(adapter, box, radius, paint)
}

add_box_lines :: #force_inline proc(
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_box_proc != nil)
	adapter.add_box_lines_proc(adapter, box, radius, thickness, paint)
}

add_arc :: proc(
	center: Vector2,
	inner_radius, outer_radius, start_angle, end_angle: f32,
	paint: Paint_Variant,
) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_arc_proc != nil)
	adapter.add_arc_proc(
		adapter,
		center,
		inner_radius,
		outer_radius,
		start_angle,
		end_angle,
		paint,
	)
}

add_circle :: #force_inline proc(center: Vector2, radius: f32, paint: Paint_Variant) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_circle_proc != nil)
	adapter.add_circle_proc(adapter, center, radius, paint)
}

add_circle_lines :: #force_inline proc(
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_circle_lines_proc != nil)
	adapter.add_circle_lines_proc(adapter, center, radius, thickness, paint)
}

add_lines :: #force_inline proc(points: []Vector2, thickness: f32, paint: Paint_Variant) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_lines_proc != nil)
	adapter.add_lines_proc(adapter, points, thickness, paint)
}

add_polygon :: #force_inline proc(points: []Vector2, paint: Paint_Variant) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_polygon_proc != nil)
	adapter.add_polygon_proc(adapter, points, paint)
}

add_glyph :: #force_inline proc(
	point: Vector2,
	scale: f32,
	font_impl: ^Font_Impl,
	codepoint: rune,
	paint: Paint_Variant,
) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_glyph_proc != nil)
	adapter.add_glyph_proc(adapter, point, scale, font_impl, codepoint, paint)
}

add_box_shadow :: #force_inline proc(box: Box, radius: f32, blur_radius: f32, color: Color) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.add_box_shadow_proc != nil)
	adapter.add_box_shadow_proc(adapter, box, radius, blur_radius, color)
}

push_scissor :: #force_inline proc(box: Box, radius: [4]f32) {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.push_scissor_proc != nil)
	adapter.push_scissor_proc(adapter, box, radius)
}

pop_scissor :: #force_inline proc() {
	adapter := &global_ctx.graphics_adapter
	assert(adapter.pop_scissor_proc != nil)
	adapter.pop_scissor_proc(adapter)
}

push_matrix :: proc() {
	assert(global_ctx.graphics_adapter.push_matrix_proc != nil)
	global_ctx.graphics_adapter.push_matrix_proc(&global_ctx.graphics_adapter)
}

pop_matrix :: proc() {
	assert(global_ctx.graphics_adapter.pop_matrix_proc != nil)
	global_ctx.graphics_adapter.pop_matrix_proc(&global_ctx.graphics_adapter)
}

translate :: proc(vector: Vector2) {
	assert(global_ctx.graphics_adapter.translate_proc != nil)
	global_ctx.graphics_adapter.translate_proc(&global_ctx.graphics_adapter, vector)
}

scale :: proc(scale: Vector2) {
	assert(global_ctx.graphics_adapter.scale_proc != nil)
	global_ctx.graphics_adapter.scale_proc(&global_ctx.graphics_adapter, scale)
}

rotate :: proc(angle: f32) {
	assert(global_ctx.graphics_adapter.rotate_proc != nil)
	global_ctx.graphics_adapter.rotate_proc(&global_ctx.graphics_adapter, angle)
}

set_draw_order :: proc(order: int) {
	assert(global_ctx.graphics_adapter.set_draw_order_proc != nil)
	global_ctx.graphics_adapter.set_draw_order_proc(&global_ctx.graphics_adapter, order)
}
