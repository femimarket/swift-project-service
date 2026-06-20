//! Adobe XMP Toolkit FFI shim for ProjectService.
//!
//! Exposes a small C ABI for embedding and reading five XMP fields:
//!
//! - prompt → `dc:description` (Lang Alt) and `Iptc4xmpExt:AIPromptInformation`
//! - model  → `xmp:CreatorTool` and `Iptc4xmpExt:AISystemUsed`
//! - subject → `dc:subject` (unordered Bag)
//!
//! Each function takes a file path. The `xmp_toolkit` smart handler updates
//! the file in place — JPEG APP1, PNG iTXt, MP4 `uuid` box, etc.

use std::ffi::{c_char, c_int, CStr};

use xmp_toolkit::{xmp_ns, OpenFileOptions, XmpFile, XmpMeta, XmpValue};

const IPTC_EXT_NS: &str = "http://iptc.org/std/Iptc4xmpExt/2008-02-29/";

unsafe fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

unsafe fn write_str(buf: *mut c_char, buf_len: c_int, s: &str) -> c_int {
    if buf.is_null() || buf_len <= 0 {
        return -1;
    }
    let bytes = s.as_bytes();
    let cap = (buf_len as usize).saturating_sub(1);
    let len = bytes.len().min(cap);
    std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, buf, len);
    *buf.add(len) = 0;
    len as c_int
}

fn open_for_update(path: &str) -> Result<XmpFile, i32> {
    let mut f = XmpFile::new().map_err(|_| -2)?;
    f.open_file(path, OpenFileOptions::default().for_update().use_smart_handler())
        .map_err(|_| -3)?;
    Ok(f)
}

fn open_for_read(path: &str) -> Result<XmpFile, i32> {
    let mut f = XmpFile::new().map_err(|_| -2)?;
    f.open_file(path, OpenFileOptions::default().for_read().use_smart_handler())
        .map_err(|_| -3)?;
    Ok(f)
}

fn load_meta(file: &mut XmpFile) -> XmpMeta {
    file.xmp().unwrap_or_else(|| XmpMeta::new().unwrap())
}

/// Embed prompt, model, and subject into `path`. Any argument may be NULL
/// (or for `subject`, count <= 0) to skip that field.
///
/// Returns 0 on success, negative on error.
#[no_mangle]
pub unsafe extern "C" fn psxmp_embed(
    path: *const c_char,
    prompt: *const c_char,
    model: *const c_char,
    subject: *const *const c_char,
    subject_count: c_int,
) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let mut file = match open_for_update(p) {
        Ok(f) => f,
        Err(e) => return e,
    };
    let mut meta = load_meta(&mut file);

    if let Some(s) = cstr(prompt) {
        if meta
            .set_localized_text(xmp_ns::DC, "description", None, "x-default", s)
            .is_err()
        {
            return -10;
        }
        if meta
            .set_property(IPTC_EXT_NS, "AIPromptInformation", &XmpValue::new(s.to_owned()))
            .is_err()
        {
            return -11;
        }
    }
    if let Some(s) = cstr(model) {
        if meta
            .set_property(xmp_ns::XMP, "CreatorTool", &XmpValue::new(s.to_owned()))
            .is_err()
        {
            return -12;
        }
        if meta
            .set_property(IPTC_EXT_NS, "AISystemUsed", &XmpValue::new(s.to_owned()))
            .is_err()
        {
            return -13;
        }
    }
    if !subject.is_null() && subject_count > 0 {
        let _ = meta.delete_property(xmp_ns::DC, "subject");
        let array_name = XmpValue::new("subject".to_owned()).set_is_array(true);
        for i in 0..subject_count {
            let item_ptr = *subject.add(i as usize);
            let Some(item) = cstr(item_ptr) else { continue };
            if meta
                .append_array_item(xmp_ns::DC, &array_name, &XmpValue::new(item.to_owned()))
                .is_err()
            {
                return -15;
            }
        }
    }

    if !file.can_put_xmp(&meta) {
        return -20;
    }
    if file.put_xmp(&meta).is_err() {
        return -21;
    }
    file.close();
    0
}

/// Read prompt (`Iptc4xmpExt:AIPromptInformation`, falling back to
/// `dc:description[x-default]`). Writes UTF-8 + NUL into `buf`, returns
/// number of bytes written (excluding NUL), 0 if absent, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_prompt(
    path: *const c_char,
    buf: *mut c_char,
    buf_len: c_int,
) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    if let Some(v) = meta.property(IPTC_EXT_NS, "AIPromptInformation") {
        return write_str(buf, buf_len, v.value.as_str());
    }
    if let Some((v, _)) = meta.localized_text(xmp_ns::DC, "description", None, "x-default") {
        return write_str(buf, buf_len, v.value.as_str());
    }
    0
}

/// Read model (`Iptc4xmpExt:AISystemUsed`, falling back to `xmp:CreatorTool`).
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_model(
    path: *const c_char,
    buf: *mut c_char,
    buf_len: c_int,
) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    if let Some(v) = meta.property(IPTC_EXT_NS, "AISystemUsed") {
        return write_str(buf, buf_len, v.value.as_str());
    }
    if let Some(v) = meta.property(xmp_ns::XMP, "CreatorTool") {
        return write_str(buf, buf_len, v.value.as_str());
    }
    0
}

/// Returns the number of subject (dc:subject) entries, 0 if absent, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_subject_count(path: *const c_char) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    meta.array_len(xmp_ns::DC, "subject") as c_int
}

/// Read the subject at `index` (0-based). Writes UTF-8 + NUL into `buf`,
/// returns bytes written (excluding NUL), 0 if absent, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_subject_at(
    path: *const c_char,
    index: c_int,
    buf: *mut c_char,
    buf_len: c_int,
) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    // XMP arrays are 1-indexed.
    let xmp_index = (index as i32) + 1;
    match meta.array_item(xmp_ns::DC, "subject", xmp_index) {
        Some(v) => write_str(buf, buf_len, v.value.as_str()),
        None => 0,
    }
}

/// Set `xmp:Rating` to `rating` (typically 0..=5). Returns 0 on success.
#[no_mangle]
pub unsafe extern "C" fn psxmp_set_rating(path: *const c_char, rating: c_int) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let mut file = match open_for_update(p) {
        Ok(f) => f,
        Err(e) => return e,
    };
    let mut meta = load_meta(&mut file);
    if meta
        .set_property_i32(xmp_ns::XMP, "Rating", &XmpValue::new(rating))
        .is_err()
    {
        return -30;
    }
    if !file.can_put_xmp(&meta) {
        return -31;
    }
    if file.put_xmp(&meta).is_err() {
        return -32;
    }
    file.close();
    0
}

/// Read `xmp:Rating`. Returns the integer rating on success, -100 when
/// absent, -1 on error. The -100 sentinel keeps the absent state
/// distinguishable from a real 0 ("unrated") value.
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_rating(path: *const c_char) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    match meta.property_i32(xmp_ns::XMP, "Rating") {
        Some(v) => v.value as c_int,
        None => -100,
    }
}

/// Read an arbitrary simple XMP property by namespace URI + name. Useful for
/// test verification (e.g. proving `Iptc4xmpExt:AIPromptInformation` is on
/// disk). Writes UTF-8 + NUL into `buf`, returns bytes written, 0 if absent.
#[no_mangle]
pub unsafe extern "C" fn psxmp_read_property(
    path: *const c_char,
    namespace: *const c_char,
    name: *const c_char,
    buf: *mut c_char,
    buf_len: c_int,
) -> c_int {
    let Some(p) = cstr(path) else { return -1 };
    let Some(ns) = cstr(namespace) else { return -1 };
    let Some(n) = cstr(name) else { return -1 };
    let Ok(mut file) = open_for_read(p) else { return -1 };
    let meta = load_meta(&mut file);
    match meta.property(ns, n) {
        Some(v) => write_str(buf, buf_len, v.value.as_str()),
        None => 0,
    }
}
