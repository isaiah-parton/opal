package opal

Font_Glyph :: struct {
	box: Box,
	advance: f32,
	codepoint: rune,
}

Font_Get_Glyph_Proc :: #type proc(impl: ^Font_Impl, codepoint: rune) -> (glyph: Font_Glyph, ok: bool)
Font_Get_Line_Height_Proc :: #type proc(impl: ^Font_Impl) -> (line_height: f32)
Font_Get_Ascend_Proc :: #type proc(impl: ^Font_Impl) -> (ascend: f32)
Font_Get_Space_Advance_Proc :: #type proc(impl: ^Font_Impl) -> (advance: f32)

Font_Impl :: struct {
	data: rawptr,
	get_glyph_proc: Font_Get_Glyph_Proc,
	get_line_height_proc: Font_Get_Line_Height_Proc,
	get_ascend_proc: Font_Get_Ascend_Proc,
	get_space_advance_proc: Font_Get_Space_Advance_Proc,
}

font_impl_get_glyph :: proc(self: ^Font_Impl, codepoint: rune) -> (glyph: Font_Glyph, ok: bool) {
	assert(self.get_glyph_proc != nil)
	return self.get_glyph_proc(self, codepoint)
}

font_impl_get_line_height :: proc(self: ^Font_Impl) -> (line_height: f32) {
	assert(self.get_line_height_proc != nil)
	return self.get_line_height_proc(self)
}

font_impl_get_ascend :: proc(self: ^Font_Impl) -> (ascend: f32) {
	assert(self.get_ascend_proc != nil)
	return self.get_ascend_proc(self)
}

font_impl_get_space_advance :: proc(self: ^Font_Impl) -> (advance: f32) {
	assert(self.get_space_advance_proc != nil)
	return self.get_space_advance_proc(self)
}
