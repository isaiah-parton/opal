package file_explorer

import tj "../../../turbojpeg-odin"
import kn "../../katana"
import "../../opal"
import tw "../../tailwind_colors"
import "core:bytes"
import c "core:c/libc"
import "core:fmt"
import img "core:image"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:unicode/utf8"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"

Preview :: struct {
	variant: Preview_Variant,
	file:    string,
}

Preview_Variant :: union {
	Text_Preview,
	Image_Preview,
}

preview_init :: proc(self: ^Preview, file: string) -> (err: os.Error) {
	if os.is_dir(file) {
		err = os.General_Error.Invalid_File
		return
	}

	// Clone file path so we own it
	self.file = strings.clone(file)

	// Open the file
	file := os.open(self.file, os.O_RDONLY) or_return
	defer os.close(file)

	switch filepath.ext(self.file) {
	case ".jpg", ".jpeg", ".png", ".qoi", ".tga", ".bmp":
		self.variant = Image_Preview{}
		image_preview_init_async(&self.variant.(Image_Preview), self.file)
	case ".ttf", ".otf":
		if data, ok := os.read_entire_file(self.file); ok {
			font: stbtt.fontinfo
			if !stbtt.InitFont(&font, raw_data(data), 0) {
				fmt.eprintln("Failed to initialize font")
			}

			x, y, w, h: i32
			codepoint: rune
			for i := 0;; i += 1 {
				index := stbtt.FindGlyphIndex(&font, rune(i))
				if index != 0 && !stbtt.IsGlyphEmpty(&font, index) {
					codepoint = rune(i)
					break
				}
			}
			scale := stbtt.ScaleForPixelHeight(&font, 32)
			glyph_pixels := stbtt.GetGlyphBitmap(
				&font,
				scale,
				scale,
				i32(codepoint),
				&w,
				&h,
				&x,
				&y,
			)[:w *
			h]
			// defer stbtt.FreeBitmap(glyph_pixels, nil)
			if glyph_pixels == nil {
				fmt.eprintln("Failed to get codepoint bitmap")
			} else {
				image_pixels := make([]u8, w * h * 4)
				defer delete(image_pixels)
				for i in 0 ..< len(glyph_pixels) {
					j := i * 4
					image_pixels[j] = 0
					image_pixels[j + 1] = 0
					image_pixels[j + 2] = 0
					image_pixels[j + 3] = glyph_pixels[i]
				}
				self.variant = Image_Preview {
					resource = kn.Atlas_Resource {
						pixels = raw_data(image_pixels),
						width = int(w),
						height = int(h),
					},
				}
			}
		} else {
			fmt.eprintln("Failed to read font file")
		}
	case:
		text_preview := Text_Preview {
			data = make([]u8, 1024),
		}
		defer if err != nil do delete(text_preview.data)

		n := os.read(file, text_preview.data) or_return

		text_preview.text = string(text_preview.data[:n])

		if utf8.valid_string(text_preview.text) {
			self.variant = text_preview
		} else {
			err = os.General_Error.Unsupported
		}
	}

	return
}

preview_uninit :: proc(self: ^Preview) {
	switch &variant in self.variant {
	case Text_Preview:
		delete(variant.data)
	case Image_Preview:
		image_preview_destroy(&variant)
	}
	delete(self.file)
	self^ = {}
}

Text_Preview :: struct {
	data: []u8,
	text: string,
}

Image_Preview :: struct {
	mutex:    sync.Mutex,
	worker:   ^thread.Thread,
	file:     string,
	resource: Maybe(kn.Atlas_Resource),
}

image_preview_destroy :: proc(self: ^Image_Preview) {
	if self.worker != nil {
		thread.destroy(self.worker)
	}
	delete(self.file)
	self^ = {}
}

image_preview_init :: proc(self: ^Image_Preview) -> (err: os.Error) {
	image: ^img.Image
	defer if image != nil do img.destroy(image)

	switch filepath.ext(self.file) {
	case ".jpg", ".jpeg":
		data := os.read_entire_file_from_filename_or_err(self.file) or_return
		defer delete(data)

		// Prepare decompressor instance
		h := tj.init_decompress()
		defer tj.destroy(h)

		// Decompress header
		width, height: c.int
		tj.decompress_header(h, raw_data(data), c.ulong(len(data)), &width, &height)

		// Prepare destination buffer
		pixels := make([]u8, int(width) * int(height) * 4)
		defer delete(pixels)

		// Decompress pixels
		tj.decompress2(
			h,
			raw_data(data),
			c.ulong(len(data)),
			raw_data(pixels),
			width,
			0,
			height,
			.RGBA,
			{.FASTDCT},
		)

		// Create image
		image = new_clone(
			img.Image{width = int(width), height = int(height), channels = 4, depth = 8},
		)

		// Populate image pixel buffer
		bytes.buffer_write(&image.pixels, pixels)
	case ".png", ".qoi", ".tga", ".bmp":
		if loaded_image, err := img.load_from_file(self.file, {.alpha_add_if_missing});
		   err == nil {
			image = loaded_image
		} else {
			fmt.eprintln(err)
		}
	case:
		return
	}

	assert(image != nil)

	MAX_DIMENSION :: 512

	shrink_x := max(image.width - MAX_DIMENSION, 0)
	shrink_y := max(image.height - MAX_DIMENSION, 0)

	new_width := image.width
	new_height := image.height
	if shrink_x > shrink_y {
		new_width = image.width - shrink_x
		new_height = int(f32(image.height) * (f32(new_width) / f32(image.width)))
	} else {
		new_height = image.height - shrink_y
		new_width = int(f32(image.width) * (f32(new_height) / f32(image.height)))
	}

	new_data := make([]u8, new_width * new_height * 4)

	stbi.resize_uint8(
		raw_data(image.pixels.buf),
		i32(image.width),
		i32(image.height),
		0,
		raw_data(new_data),
		i32(new_width),
		i32(new_height),
		0,
		4,
	)

	sync.guard(&self.mutex)
	self.resource = kn.Atlas_Resource {
		pixels = raw_data(new_data),
		width  = new_width,
		height = new_height,
	}

	return
}

image_preview_init_async :: proc(self: ^Image_Preview, file: string) {
	self.file = strings.clone(file)
	self.worker = thread.create_and_start_with_data(self, proc(data: rawptr) {
		self := (^Image_Preview)(data)
		image_preview_init(self)
	})
}

File_Previews :: struct {
	items: [dynamic]^Preview,
	mutex: sync.Mutex,
}

file_previews_add :: proc(
	self: ^File_Previews,
	file: string,
) -> (
	preview: ^Preview,
	err: os.Error,
) {
	sync.guard(&self.mutex)
	preview = new(Preview)
	preview_init(preview, file) or_return
	append(&self.items, preview)
	return
}

file_previews_clear :: proc(self: ^File_Previews) {
	sync.guard(&self.mutex)
	for item in self.items {
		preview_uninit(item)
		free(item)
	}
	clear(&self.items)
}

file_previews_clear_except :: proc(self: ^File_Previews, items: []Item) {
	sync.guard(&self.mutex)
	loop: for &preview, i in self.items {
		for &item in items {
			if preview.file == item.fullpath {
				continue loop
			}
		}
		preview_uninit(preview)
		free(preview)
		ordered_remove(&self.items, i)
	}
}

file_previews_destroy :: proc(self: ^File_Previews) {
	file_previews_clear(self)
	delete(self.items)
	self^ = {}
}

file_previews_display :: proc(self: ^File_Previews) {
	using opal

	sync.mutex_guard(&self.mutex)

	for item, i in self.items {
		push_id(int(i + 1))
		defer pop_id()

		switch &variant in item.variant {
		case (Text_Preview):
			do_text(
				&{sizing = {grow = 1, max = INFINITY, fit = 1}},
				variant.text,
				14,
				&global_ctx.theme.monospace_font,
				global_ctx.theme.color.base_foreground,
			)
		case (Image_Preview):
			if resource, ok := variant.resource.?; ok {
				size := [2]f32{f32(resource.width), f32(resource.height)}
				add_node(
					&{
						sizing = {grow = 1, max = size, aspect_ratio = size.x / size.y},
						data = item,
						on_draw = proc(node: ^Node) {
							app := (^Explorer)(node.data)
							resource := &(^Image_Preview)(node.data).resource.?
							kn.add_box(
								node.box,
								4,
								kn.make_atlas_sample(resource, node.box, kn.WHITE) if resource.pixels != nil else tw.TRANSPARENT,
							)
							kn.add_box_lines(node.box, 2, 4, global_ctx.theme.color.border)
						},
					},
				)
			}
		}
	}
}

