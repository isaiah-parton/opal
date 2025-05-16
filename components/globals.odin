package components

import ".."

Theme :: struct {
	icon_font:    ^opal.Font,
	border_color: opal.Color,
	base_size:    [2]f32,
}

@(private)
theme: Theme = {
	base_size = 16,
}

get_global_theme :: proc() -> ^Theme {
	return &theme
}

