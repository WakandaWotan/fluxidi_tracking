"""Rasterize ordinary receipt proof PDFs (before/after logo + addresses)."""
from __future__ import annotations

import pathlib

import fitz
from PIL import Image
import io

proof = pathlib.Path(__file__).resolve().parent
pairs = [
    ("ordinary_receipt_BEFORE_small_logo.pdf", "ordinary_receipt_BEFORE_page1.png"),
    ("ordinary_receipt_AFTER_large_logo.pdf", "ordinary_receipt_AFTER_page1.png"),
    ("business_invoice_layout_UNCHANGED.pdf", "business_invoice_layout_UNCHANGED_page1.png"),
]
for pdf_name, png_name in pairs:
    pdf_path = proof / pdf_name
    doc = fitz.open(pdf_path)
    page = doc[0]
    pix = page.get_pixmap(matrix=fitz.Matrix(150 / 72, 150 / 72), alpha=False)
    out = proof / png_name
    pix.save(out)
    img = Image.open(io.BytesIO(pix.tobytes("png"))).convert("RGB")
    # Upper-left logo region + route text band
    crop = img.crop((30, 30, 900, 420))
    crop_path = proof / png_name.replace("_page1.png", "_header_crop.png")
    crop.save(crop_path)
    print(pdf_name, "->", out.name, crop_path.name, f"{img.size[0]}x{img.size[1]}")
