package opal

Painter_Add_Box_Proc :: #type proc(box: Box, radius: [4]f32, paint: Paint_Variant)
Painter_Add_Box_Lines_Proc :: #type proc(
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
)
Painter_Add_Circle_Proc :: #type proc(center: Vector2, radius: f32, paint: Paint_Variant)
Painter_Add_Circle_Lines_Proc :: #type proc(
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
)
Painter_Add_Polygon_Proc :: #type proc(points: []Vector2, paint: Paint_Variant)
Painter_Add_Polygon_Lines_Proc :: #type proc(
	points: []Vector2,
	thickness: f32,
	paint: Paint_Variant,
)
Painter_Push_Scissor_Proc :: #type proc(box: Box, radius: [4]f32)
Painter_Pop_Scissor_Proc :: #type proc()
Painter_Push_Matrix_Proc :: #type proc()
Painter_Pop_Matrix_Proc :: #type proc()
Painter_Translate_Proc :: #type proc(vector: Vector2)
Painter_Scale_Proc :: #type proc(scale: Vector2)
Painter_Rotate_Proc :: #type proc(angle: f32)
Painter_Add_Glyph_Proc :: #type proc(point: Vector2, scale: f32, glyph: Glyph)

Painter_Impl :: struct {
	add_box_proc:           Painter_Add_Box_Proc,
	add_box_lines_proc:     Painter_Add_Box_Lines_Proc,
	add_circle_proc:        Painter_Add_Circle_Proc,
	add_circle_lines_proc:  Painter_Add_Circle_Lines_Proc,
	add_polygon_proc:       Painter_Add_Polygon_Proc,
	add_polygon_lines_proc: Painter_Add_Polygon_Lines_Proc,
	add_glyph_proc: Painter_Add_Glyph_Proc,
	push_scissor_proc:      Painter_Push_Scissor_Proc,
	pop_scissor_proc:       Painter_Pop_Scissor_Proc,
	push_matrix_proc:       Painter_Push_Matrix_Proc,
	pop_matrix_proc:        Painter_Pop_Matrix_Proc,
	translate_proc:         Painter_Translate_Proc,
	scale_proc:             Painter_Scale_Proc,
	rotate_proc:            Painter_Rotate_Proc,
}

painter_impl_push_scissor :: proc(self: ^Painter_Impl, box: Box, radius: [4]f32) {
	assert(self.push_scissor_proc != nil)
	self.push_scissor_proc(box, radius)
}

painter_impl_pop_scissor :: proc(self: ^Painter_Impl) {
	assert(self.pop_scissor_proc != nil)
	self.pop_scissor_proc()
}

painter_impl_add_glyph :: proc(self: ^Painter_Impl, point: Vector2, scale: f32, glyph: Glyph) {
	assert(self.add_glyph_proc != nil)
	self.add_glyph_proc(point, scale, glyph)
}

painter_impl_add_box :: proc(self: ^Painter_Impl, box: Box, radius: [4]f32, paint: Paint_Variant) {
	assert(self.add_box_proc != nil)
	self.add_box_proc(box, radius, paint)
}

painter_impl_add_box_lines :: proc(
	self: ^Painter_Impl,
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_box_lines_proc(box, radius, thickness, paint)
}

painter_impl_add_circle :: proc(
	self: ^Painter_Impl,
	center: Vector2,
	radius: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_proc != nil)
	self.add_circle_proc(center, radius, paint)
}

painter_impl_add_circle_lines :: proc(
	self: ^Painter_Impl,
	center: Vector2,
	radius: f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_circle_lines_proc(center, radius, thickness, paint)
}

painter_impl_add_polygon :: proc(self: ^Painter_Impl, points: []Vector2, paint: Paint_Variant) {
	assert(self.add_box_proc != nil)
	self.add_polygon_proc(points, paint)
}

painter_impl_add_polygon_lines :: proc(
	self: ^Painter_Impl,
	points: []Vector2,
	thickness: f32,
	paint: Paint_Variant,
) {
	assert(self.add_box_lines_proc != nil)
	self.add_polygon_lines_proc(points, thickness, paint)
}

add_box :: #force_inline proc(box: Box, radius: [4]f32, paint: Paint_Variant) {
	painter_impl_add_box(&global_ctx.painter_impl, box, radius, paint)
}

add_box_lines :: #force_inline proc(
	box: Box,
	radius: [4]f32,
	thickness: f32,
	paint: Paint_Variant,
) {
	painter_impl_add_box_lines(&global_ctx.painter_impl, box, radius, thickness, paint)
}

add_circle :: #force_inline proc(center: Vector2, radius: f32, paint: Paint_Variant) {
	painter_impl_add_circle(&global_ctx.painter_impl, center, radius, paint)
}

add_circle_lines :: #force_inline  proc(center: Vector2, radius: f32, thickness: f32, paint: Paint_Variant) {
	painter_impl_add_circle_lines(&global_ctx.painter_impl, center, radius, thickness, paint)
}

add_polygon :: #force_inline proc(points: []Vector2, paint: Paint_Variant) {
	painter_impl_add_polygon(&global_ctx.painter_impl, points, paint)
}

add_polygon_lines :: #force_inline  proc(points: []Vector2, thickness: f32, paint: Paint_Variant) {
	painter_impl_add_polygon_lines(&global_ctx.painter_impl, points, thickness, paint)
}

push_scissor :: #force_inline proc(box: Box, radius: [4]f32) {
	painter_impl_push_scissor(&global_ctx.painter_impl, box, radius)
}

pop_scissor :: #force_inline proc() {
	painter_impl_pop_scissor(&global_ctx.painter_impl)
}

push_matrix :: proc() {
	assert(&global_ctx.painter_impl.push_matrix_proc != nil)
	global_ctx.painter_impl.push_matrix_proc()
}

pop_matrix :: proc() {
	assert(&global_ctx.painter_impl.pop_matrix_proc != nil)
	global_ctx.painter_impl.pop_matrix_proc()
}

translate :: proc(vector: Vector2) {
	assert(&global_ctx.painter_impl.translate_proc != nil)
	global_ctx.painter_impl.translate_proc(vector)
}

scale :: proc(scale: Vector2) {
	assert(&global_ctx.painter_impl.scale_proc != nil)
	global_ctx.painter_impl.scale_proc(scale)
}

rotate :: proc(angle: f32) {
	assert(&global_ctx.painter_impl.rotate_proc != nil)
	global_ctx.painter_impl.rotate_proc(angle)
}
