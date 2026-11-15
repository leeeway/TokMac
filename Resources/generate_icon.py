import math
from PIL import Image, ImageDraw

def create_app_icon():
    size = 1024
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # 1. Base Squircle (macOS rounded rect)
    mask = Image.new('L', (size, size), 0)
    draw_mask = ImageDraw.Draw(mask)
    margin = 80
    corner_radius = 210
    draw_mask.rounded_rectangle(
        [(margin, margin), (size - margin, size - margin)],
        radius=corner_radius,
        fill=255
    )
    
    # 2. Background Gradient (midnight black with subtle dark purple-blue sheen)
    bg = Image.new('RGBA', (size, size), (18, 18, 24, 255))
    bg_draw = ImageDraw.Draw(bg)
    # Add subtle border highlight
    bg_draw.rounded_rectangle(
        [(margin, margin), (size - margin, size - margin)],
        radius=corner_radius,
        outline=(50, 50, 65, 255),
        width=4
    )
    
    # 3. Draw TikTok Note / Musical Glyph
    # We will draw Cyan, Red, and White layers
    # Scaled coordinates for a 1024 icon
    
    def draw_glyph(color, offset_x, offset_y):
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        
        cx = size // 2 + offset_x
        cy = size // 2 + offset_y - 20
        
        # Stem & Flag:
        # Note stem
        stem_left = cx - 20
        stem_right = cx + 50
        stem_top = cy - 220
        stem_bottom = cy + 100
        
        # Bottom circle/bulb of note
        bulb_cx = cx - 70
        bulb_cy = cy + 100
        bulb_r = 110
        
        # Top flag / hook:
        hook_cx = cx + 50
        hook_cy = cy - 220
        
        # Draw stem
        d.rectangle([(stem_left, stem_top), (stem_right, stem_bottom)], fill=color)
        
        # Draw bulb
        d.ellipse([
            (bulb_cx - bulb_r, bulb_cy - bulb_r + 20),
            (bulb_cx + bulb_r, bulb_cy + bulb_r + 20)
        ], fill=color)
        
        # Draw upper curve (hook)
        d.arc([
            (hook_cx - 30, hook_cy - 40),
            (hook_cx + 260, hook_cy + 250)
        ], start=270, end=360, fill=color, width=70)
        d.arc([
            (hook_cx - 30, hook_cy + 40),
            (hook_cx + 190, hook_cy + 260)
        ], start=270, end=360, fill=color, width=70)
        
        return layer

    cyan = (37, 244, 238, 230)
    red = (254, 44, 85, 230)
    white = (255, 255, 255, 255)
    
    cyan_layer = draw_glyph(cyan, -22, -10)
    red_layer = draw_glyph(red, 22, 10)
    white_layer = draw_glyph(white, 0, 0)
    
    # Composite glyphs
    bg.paste(cyan_layer, (0, 0), cyan_layer)
    bg.paste(red_layer, (0, 0), red_layer)
    bg.paste(white_layer, (0, 0), white_layer)
    
    # Apply squircle mask
    img.paste(bg, (0, 0), mask)
    
    img.save('/Users/leeway/github/TokMac/Resources/AppIcon_1024.png')
    print("Icon generated successfully!")

if __name__ == '__main__':
    create_app_icon()
