"""Use native Word PDF export as the backend for the packaged DOCX PNG renderer.

The Windows dependency bundle contains Poppler but no LibreOffice. The exported
PDF is the actual rendering of this DOCX in Word, not a separately laid-out file.
"""
from pathlib import Path
import importlib.util
import os
import sys

ROOT = Path(__file__).resolve().parent
SKILL = Path.home() / ".codex/plugins/cache/openai-primary-runtime/documents/26.1017.22136/skills/documents"
POPPLER = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin"
DOCX = ROOT / "Delta robot fly tracking user manual.docx"
PDF = DOCX.with_suffix(".pdf")
if not PDF.is_file():
    raise FileNotFoundError("Export the DOCX with export_word_pdf.ps1 before rendering.")
os.environ["PATH"] = str(POPPLER) + os.pathsep + os.environ.get("PATH", "")
spec = importlib.util.spec_from_file_location("packaged_docx_renderer", SKILL / "render_docx.py")
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)
renderer.convert_to_pdf = lambda *args, **kwargs: (str(PDF), "Native Word fixed-format export")
sys.argv = [str(SKILL / "render_docx.py"), str(DOCX), "--output_dir", str(ROOT / "qa"), "--dpi", "145"]
renderer.main()
