#!/usr/bin/env python3
import sys
import os
import json
import base64
import subprocess
import mimetypes
import zipfile
import xml.etree.ElementTree as ET
import urllib.parse
import tempfile
import selectors
import time

MAX_INPUT_BYTES = 50 * 1024 * 1024
MAX_TEXT_BYTES = 20 * 1024 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024

def _run_text_command(argv, timeout):
    """Run an extractor with bounded in-memory output and a hard timeout."""
    with tempfile.TemporaryFile() as output_file, tempfile.TemporaryFile() as error_file:
        proc = subprocess.Popen(argv, stdout=output_file, stderr=error_file)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
            raise TimeoutError("document extractor timed out")
        output_file.seek(0)
        error_file.seek(0)
        output = output_file.read(MAX_TEXT_BYTES + 1)
        error = error_file.read(1024 * 1024)
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, argv, output=output, stderr=error)
    if len(output) > MAX_TEXT_BYTES:
        raise ValueError("document text is too large")
    return output.decode("utf-8")


def extract_docx_text(path):
    # Try pandoc first
    try:
        return _run_text_command(['pandoc', '-f', 'docx', '-t', 'markdown', path], 30)
    except Exception:
        pass
    
    # Fallback to direct XML parsing
    try:
        with zipfile.ZipFile(path) as docx:
            if sum(info.file_size for info in docx.infolist()) > MAX_TEXT_BYTES:
                raise ValueError("compressed document expands beyond the supported size")
            xml_content = docx.read('word/document.xml')
            if len(xml_content) > MAX_TEXT_BYTES:
                raise ValueError("document text is too large")
            root = ET.fromstring(xml_content)
            paragraphs = []
            namespace = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
            for p in root.iter(namespace + 'p'):
                p_text = []
                for t in p.iter(namespace + 't'):
                    if t.text:
                        p_text.append(t.text)
                paragraphs.append("".join(p_text))
            return "\n".join(paragraphs)
    except Exception as e:
        raise Exception(f"Failed to read docx. Try installing 'pandoc' (Debian/Ubuntu: apt install pandoc, Arch: pacman -S pandoc-cli, Fedora: dnf install pandoc) for robust parsing. Error: {str(e)}")

def extract_pdf_text(path):
    try:
        return _run_text_command(['pdftotext', path, '-'], 30)
    except FileNotFoundError:
        raise Exception("pdftotext is not installed. Please install 'poppler-utils' (Debian/Ubuntu: apt install poppler-utils, Arch: pacman -S poppler, Fedora: dnf install poppler-utils) to enable PDF attachment reading.")
    except Exception as e:
        raise Exception(f"Failed to extract PDF contents. Error: {str(e)}")

def extract_single_file(file_path):
    if not os.path.exists(file_path):
        return {
            "status": "error",
            "message": f"File not found: {file_path}"
        }

    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    if file_size > MAX_INPUT_BYTES:
        return {"status": "error", "message": "File is larger than the 50 MiB attachment limit"}
    
    # Guess mime type
    mime_type, _ = mimetypes.guess_type(file_path)
    ext = os.path.splitext(filename)[1].lower()

    if not mime_type:
        if ext == '.docx':
            mime_type = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        elif ext == '.csv':
            mime_type = 'text/csv'
        elif ext == '.pdf':
            mime_type = 'application/pdf'
        else:
            mime_type = 'application/octet-stream'

    try:
        # Check if it's an image
        if mime_type.startswith('image/') or ext in ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']:
            if file_size > MAX_IMAGE_BYTES:
                return {"status": "error", "message": "Image is larger than the 20 MiB attachment limit"}
            with open(file_path, 'rb') as f:
                img_data = f.read(MAX_IMAGE_BYTES + 1)
            if len(img_data) > MAX_IMAGE_BYTES:
                return {"status": "error", "message": "Image is larger than the 20 MiB attachment limit"}
            base64_data = base64.b64encode(img_data).decode('utf-8')
            
            actual_mime = mime_type if mime_type.startswith('image/') else 'image/jpeg'
            return {
                "status": "success",
                "type": "image",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": actual_mime,
                "content": base64_data
            }
        elif ext == '.pdf':
            text = extract_pdf_text(file_path)
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": "application/pdf",
                "content": text
            }
        elif ext == '.docx':
            text = extract_docx_text(file_path)
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": mime_type,
                "content": text
            }
        elif mime_type.startswith('text/') or ext in ['.csv', '.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.js', '.ts', '.py', '.sh', '.html', '.css']:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    text = f.read(MAX_TEXT_BYTES + 1)
                if len(text) > MAX_TEXT_BYTES:
                    return {"status": "error", "message": "Text attachment is larger than the 20 MiB limit"}
            except UnicodeDecodeError:
                with open(file_path, 'r', encoding='latin-1') as f:
                    text = f.read(MAX_TEXT_BYTES + 1)
                if len(text) > MAX_TEXT_BYTES:
                    return {"status": "error", "message": "Text attachment is larger than the 20 MiB limit"}
            
            return {
                "status": "success",
                "type": "text",
                "filename": filename,
                "path": file_path,
                "size": file_size,
                "mimeType": mime_type or 'text/plain',
                "content": text
            }
        else:
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    text = f.read(MAX_TEXT_BYTES + 1)
                if len(text) > MAX_TEXT_BYTES:
                    return {"status": "error", "message": "Text attachment is larger than the 20 MiB limit"}
                return {
                    "status": "success",
                    "type": "text",
                    "filename": filename,
                    "path": file_path,
                    "size": file_size,
                    "mimeType": 'text/plain',
                    "content": text
                }
            except Exception:
                return {
                    "status": "error",
                    "message": f"Unsupported file type: {mime_type}"
                }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e)
        }

def get_clipboard_targets():
    # Try wl-paste first (Wayland)
    try:
        res = subprocess.run(['wl-paste', '-l'], capture_output=True, text=True, check=True, timeout=5)
        return res.stdout[:65536].splitlines()
    except Exception:
        pass
    
    # Try xclip (X11)
    try:
        res = subprocess.run(['xclip', '-selection', 'clipboard', '-t', 'TARGETS', '-o'], capture_output=True, text=True, check=True, timeout=5)
        return res.stdout[:65536].splitlines()
    except Exception:
        pass
    
    return []

def get_clipboard_data(mime_type, max_bytes=MAX_TEXT_BYTES):
    """Read clipboard data without allowing an unbounded subprocess pipe."""
    commands = [
        ['wl-paste', '-t', mime_type],
        ['xclip', '-selection', 'clipboard', '-t', mime_type, '-o'],
    ]
    for command in commands:
        proc = None
        selector = selectors.DefaultSelector()
        try:
            proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            selector.register(proc.stdout, selectors.EVENT_READ)
            data = bytearray()
            deadline = time.monotonic() + 5
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("clipboard read timed out")
                events = selector.select(min(remaining, 0.25))
                for key, _ in events:
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    data.extend(chunk)
                    if len(data) > max_bytes:
                        raise ValueError("clipboard data is too large")
            proc.wait(timeout=1)
            if proc.returncode == 0:
                return bytes(data)
        except Exception:
            if proc is not None:
                try: proc.kill()
                except Exception: pass
                try: proc.wait()
                except Exception: pass
        finally:
            selector.close()
            if proc is not None and proc.stdout is not None:
                try: proc.stdout.close()
                except Exception: pass
    return None

def handle_clipboard():
    targets = get_clipboard_targets()
    
    # 1. Check for text/uri-list (files copied in file manager)
    has_uri_list = False
    for t in targets:
        if 'uri-list' in t:
            has_uri_list = True
            break
            
    if has_uri_list:
        data = get_clipboard_data('text/uri-list')
        if data:
            try:
                uri_str = data.decode('utf-8')
            except Exception:
                uri_str = data.decode('latin-1')
            
            lines = [line.strip() for line in uri_str.splitlines() if line.strip()]
            files_extracted = []
            
            for line in lines[:50]:
                parsed_uri = urllib.parse.urlparse(line)
                if (parsed_uri.scheme.lower() == 'file'
                        and parsed_uri.netloc.lower() in ('', 'localhost')
                        and not parsed_uri.query and not parsed_uri.fragment):
                    path = urllib.parse.unquote(parsed_uri.path)
                    file_info = extract_single_file(path)
                    if file_info and file_info.get("status") == "success":
                        files_extracted.append(file_info)
            
            if files_extracted:
                print(json.dumps({
                    "status": "success",
                    "mode": "files",
                    "files": files_extracted
                }))
                return
                
    # 2. Check for image targets
    has_image = False
    img_mime = 'image/png'
    for t in targets:
        if t.startswith('image/'):
            has_image = True
            img_mime = t
            break
            
    if has_image:
        img_bytes = get_clipboard_data(img_mime, MAX_IMAGE_BYTES)
        if img_bytes and len(img_bytes) <= MAX_IMAGE_BYTES:
            import tempfile
            suffix = mimetypes.guess_extension(img_mime) or '.png'
            with tempfile.NamedTemporaryFile(delete=False, prefix="kdeaichat_clip_", suffix=suffix) as tmp_file:
                tmp_file.write(img_bytes)
                temp_path = tmp_file.name
            
            base64_data = base64.b64encode(img_bytes).decode('utf-8')
            filename = os.path.basename(temp_path)
            
            print(json.dumps({
                "status": "success",
                "mode": "image",
                "file": {
                    "type": "image",
                    "name": filename,
                    "path": temp_path,
                    "size": len(img_bytes),
                    "mimeType": img_mime,
                    "content": base64_data
                }
            }))
            return

    print(json.dumps({
        "status": "empty",
        "message": "Clipboard does not contain files or images"
    }))

def cleanup_temporary_file(path):
    """Remove only files created by the widget's temporary attachment paths."""
    real_path = os.path.realpath(os.path.expanduser(str(path or "")))
    temp_root = os.path.realpath(tempfile.gettempdir())
    base = os.path.basename(real_path)
    allowed_prefixes = ("kdeaichat_clip_", "kdeaichat_shot_")
    if not real_path.startswith(temp_root + os.sep) or not base.startswith(allowed_prefixes):
        return {"status": "error", "message": "Refusing to remove a non-widget temporary file"}
    try:
        os.remove(real_path)
        return {"status": "success"}
    except FileNotFoundError:
        return {"status": "success"}
    except OSError as exc:
        return {"status": "error", "message": str(exc)}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "message": "No file path provided"}))
        return

    arg = sys.argv[1]
    if arg == '--clipboard':
        handle_clipboard()
    elif arg == '--cleanup' and len(sys.argv) >= 3:
        print(json.dumps(cleanup_temporary_file(sys.argv[2])))
    else:
        result = extract_single_file(arg)
        print(json.dumps(result))

if __name__ == '__main__':
    main()
