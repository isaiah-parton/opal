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
Add_Arc_Proc :: #type proc(
	self: ^Graphics_Adapter,
	center: Vector2,
	inner_radius: f32,
	outer_radius: f32,
	start_angle: f32,
	end_angle: f32,
	paint: Paint_Variant,
)
Add_Polygon_Proc :: #type proc(self: ^Graphics_Adapter, points: []Vector2, paint: Paint_Variant)
Push_Scissor_Proc :: #type proc(self: ^Graphics_Adapter, box: Box, radius: [4]f32)
Pop_Scissor_Proc :: #type proc(self: ^Graphics_Adapter)
Push_Matrix_Proc :: #type proc(self: ^Graphics_Adapter)
Pop_Matrix_Proc :: #type proc(self: ^Graphics_Adapter)
Translate_Proc :: #type proc(self: ^Graphics_Adapter, vector: Vector2)
Scale_Proc :: #type proc(self: ^Graphics_Adapter, scale: Vector2)
Rotate_Proc :: #type proc(self: ^Graphics_Adapter, angle: f32)
Add_Glyph_Proc :: #type proc(
	self: ^Graphics_Adapter,
	point: Vector2,
	scale: f32,
	font_impl: ^Font_Impl,
	codepoint: rune,
	paint: Paint_Variant,
)
Set_Draw_Order_Proc :: #type proc(self: ^Graphics_Adapter, index: int)
Add_Box_Shadow_Proc :: #type proc(
	self: ^Graphics_Adapter,
	box: Box,
	radius: f32,
	blur_radius: f32,
	color: Color,
)
Add_Lines_Proc :: #type proc(
	self: ^Graphics_Adapter,
	points: []Vector2,
	thickness: f32,
	paint: Paint_Variant,
	closed := false,
)

Graphics_Adapter :: struct {
	data:                  rawptr,
	add_arc_proc:          Add_Arc_Proc,
	add_box_proc:          Add_Box_Proc,
	add_box_lines_proc:    Add_Box_Lines_Proc,
	add_circle_proc:       Add_Circle_Proc,
	add_circle_lines_proc: Add_Circle_Lines_Proc,
	add_polygon_proc:      Add_Polygon_Proc,
	add_lines_proc:        Add_Lines_Proc,
	add_glyph_proc:        Add_Glyph_Proc,
	add_box_shadow_proc:   Add_Box_Shadow_Proc,
	push_scissor_proc:     Push_Scissor_Proc,
	pop_scissor_proc:      Pop_Scissor_Proc,
	push_matrix_proc:      Push_Matrix_Proc,
	pop_matrix_proc:       Pop_Matrix_Proc,
	translate_proc:        Translate_Proc,
	scale_proc:            Scale_Proc,
	rotate_proc:           Rotate_Proc,
	set_draw_order_proc:   Set_Draw_Order_Proc,
}
