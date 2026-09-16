package opal

Add_Box_Proc :: #type proc(self: ^Graphics_Adapter, box: Box, radius: [4]f32, paint: Paint_Variant)
Add_Box_Lines_Proc :: #type proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
)
Add_Circle_Proc :: #type proc(
	self: ^Graphics_Adapter,
	center: Vector2,
	radius: f32,
	paint: Paint_Variant,
)
Add_Circle_Lines_Proc :: #type proc(
	self: ^Graphics_Adapter,
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
)
Add_Polygon_Proc :: #type proc(self: ^Graphics_Adapter, points: []Vector2, paint: Paint_Variant)
Add_Polygon_Lines_Proc :: #type proc(
	self: ^Graphics_Adapter,
	points: []Vector2,
	thickness: f32,
	paint: Paint_Variant,
)
Push_Scissor_Proc :: #type proc(self: ^Graphics_Adapter, box: Box, radius: [4]f32)
Pop_Scissor_Proc :: #type proc(self: ^Graphics_Adapter)
Push_Matrix_Proc :: #type proc(self: ^Graphics_Adapter)
Pop_Matrix_Proc :: #type proc(self: ^Graphics_Adapter)
Translate_Proc :: #type proc(self: ^Graphics_Adapter, vector: Vector2)
Scale_Proc :: #type proc(self: ^Graphics_Adapter, scale: Vector2)
Rotate_Proc :: #type proc(self: ^Graphics_Adapter, angle: f32)
Add_Glyph_Proc :: #type proc(self: ^Graphics_Adapter, point: Vector2, scale: f32, glyph: Glyph)
Add_Box_Shadow_Proc :: #type proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: f32,
	blur_radius: f32,
	color: Color,
)

Graphics_Adapter :: struct {
	data:                   rawptr,
	add_box_proc:           Add_Box_Proc,
	add_box_lines_proc:     Add_Box_Lines_Proc,
	add_circle_proc:        Add_Circle_Proc,
	add_circle_lines_proc:  Add_Circle_Lines_Proc,
	add_polygon_proc:       Add_Polygon_Proc,
	add_polygon_lines_proc: Add_Polygon_Lines_Proc,
	add_glyph_proc:         Add_Glyph_Proc,
	add_box_shadow_proc:    Add_Box_Shadow_Proc,
	push_scissor_proc:      Push_Scissor_Proc,
	pop_scissor_proc:       Pop_Scissor_Proc,
	push_matrix_proc:       Push_Matrix_Proc,
	pop_matrix_proc:        Pop_Matrix_Proc,
	translate_proc:         Translate_Proc,
	scale_proc:             Scale_Proc,
	rotate_proc:            Rotate_Proc,
}

graphics_adapter_add_box_shadow :: proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: f32,
	blur_radius: f32,
	color: Color,
) {
	if self.add_box_shadow_proc == nil {
		return
	}
	self.add_box_shadow_proc(self, box, radius, blur_radius, color)
}

graphics_adapter_push_scissor :: proc(self: ^Graphics_Adapter, box: Box, radius: [4]f32) {
	assert(self.push_scissor_proc != nil)
	self.push_scissor_proc(self, box, radius)
}

graphics_adapter_pop_scissor :: proc(self: ^Graphics_Adapter) {
	assert(self.pop_scissor_proc != nil)
	self.pop_scissor_proc(self)
}

graphics_adapter_add_glyph :: proc(self: ^Graphics_Adapter, point: Vector2, scale: f32, glyph: Glyph) {
	assert(self.add_glyph_proc != nil)
	self.add_glyph_proc(self, point, scale, glyph)
}

graphics_adapter_add_box :: proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: [4]f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_proc != nil)
	self.add_box_proc(self, box, radius, paint)
}

graphics_adapter_add_box_lines :: proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_box_lines_proc(self, box, radius, thickness, paint)
}

graphics_adapter_add_circle :: proc(
	self: ^Graphics_Adapter,
	center: Vector2,
	radius: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_proc != nil)
	self.add_circle_proc(self, center, radius, paint)
}

graphics_adapter_add_circle_lines :: proc(
	self: ^Graphics_Adapter,
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_circle_lines_proc(self, center, radius, thickness, paint)
}

graphics_adapter_add_polygon :: proc(
	self: ^Graphics_Adapter,
	points: []Vector2,
	paint: Paint_Variant,
) {
	assert(self.add_box_proc != nil)
	self.add_polygon_proc(self, points, paint)
}

graphics_adapter_add_polygon_lines :: proc(
	self: ^Graphics_Adapter,
	points: []Vector2,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_polygon_lines_proc(self, points, thickness, paint)
}

add_box :: #force_inline proc(box: Box, radius: [4]f32, paint: Paint_Variant) {
	graphics_adapter_add_box(&global_ctx.graphics_adapter, box, radius, paint)
}

add_box_lines :: #force_inline proc(
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	graphics_adapter_add_box_lines(&global_ctx.graphics_adapter, box, radius, thickness, paint)
}

add_circle :: #force_inline proc(center: Vector2, radius: f32, paint: Paint_Variant) {
	graphics_adapter_add_circle(&global_ctx.graphics_adapter, center, radius, paint)
}

add_circle_lines :: #force_inline proc(
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	graphics_adapter_add_circle_lines(
		&global_ctx.graphics_adapter,
		center,
		radius,
		thickness,
		paint,
	)
}

add_polygon :: #force_inline proc(points: []Vector2, paint: Paint_Variant) {
	graphics_adapter_add_polygon(&global_ctx.graphics_adapter, points, paint)
}

add_polygon_lines :: #force_inline proc(points: []Vector2, thickness: f32, paint: Paint_Variant) {
	graphics_adapter_add_polygon_lines(&global_ctx.graphics_adapter, points, thickness, paint)
}

push_scissor :: #force_inline proc(box: Box, radius: [4]f32) {
	graphics_adapter_push_scissor(&global_ctx.graphics_adapter, box, radius)
}

pop_scissor :: #force_inline proc() {
	graphics_adapter_pop_scissor(&global_ctx.graphics_adapter)
}

push_matrix :: proc() {
	assert(&global_ctx.graphics_adapter.push_matrix_proc != nil)
	global_ctx.graphics_adapter.push_matrix_proc()
}

pop_matrix :: proc() {
	assert(&global_ctx.graphics_adapter.pop_matrix_proc != nil)
	global_ctx.graphics_adapter.pop_matrix_proc()
}

translate :: proc(vector: Vector2) {
	assert(&global_ctx.graphics_adapter.translate_proc != nil)
	global_ctx.graphics_adapter.translate_proc(vector)
}

scale :: proc(scale: Vector2) {
	assert(&global_ctx.graphics_adapter.scale_proc != nil)
	global_ctx.graphics_adapter.scale_proc(scale)
}

rotate :: proc(angle: f32) {
	assert(&global_ctx.graphics_adapter.rotate_proc != nil)
	global_ctx.graphics_adapter.rotate_proc(angle)
}
