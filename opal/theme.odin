package opal

import tw "../tailwind_colors"

Theme :: struct {
	text_gap:        f32,
	checkbox_size:   f32,
	label_text_size: f32,
	label_icon_size: f32,
	min_spacing:     f32,
	radius_small:    f32,
	radius_big:      f32,
	base_size:       [2]f32,
	border_width:    f32,
	animation_time:  f32,
	font_size_small: f32,
	font:            Font_Impl,
	monospace_font:  Font_Impl,
	icon_font:       Font_Impl,
	color:           Theme_Colors,
}

Theme_Colors :: struct {
	border:               Color,
	primary:              Color,
	primary_foreground:   Color,
	secondary:            Color,
	secondary_foreground: Color,
	secondary_strong:     Color,
	accent:               Color,
	background:           Color,
	base_strong:          Color,
	base_foreground:      Color,
	selection_background: Color,
	selection_foreground: Color,
}

theme_default :: proc() -> Theme {
	return Theme {
		text_gap = 4,
		checkbox_size = 18,
		border_width = 2,
		label_text_size = 14,
		label_icon_size = 16,
		base_size = 12,
		min_spacing = 12,
		radius_small = 8,
		radius_big = 16,
		font_size_small = 14,
		color = {
			background = tw.AMBER_100,
			base_strong = color_from_rgba(
				color_from_hsla_array(
					hsla_from_rgba(rgba_from_color(tw.AMBER_200)) * [4]f32{1, 0.5, 1, 1},
				),
			),
			accent = tw.PURPLE_400,
			primary = tw.EMERALD_500,
			primary_foreground = tw.WHITE,
			secondary = tw.NEUTRAL_700,
			secondary_foreground = tw.NEUTRAL_950,
			secondary_strong = tw.NEUTRAL_600,
			border = tw.GRAY_900,
			base_foreground = tw.BLACK,
			selection_background = tw.INDIGO_500,
			selection_foreground = tw.BLACK,
		},
	}
}
