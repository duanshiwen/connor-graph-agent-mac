use std::ffi::{c_char, CStr, CString};
use std::ptr;

use crate::{ConnorMemorySearchKernel, MemorySearchRequest};

#[no_mangle]
pub extern "C" fn connor_search_open(index_dir: *const c_char, error: *mut *mut c_char) -> *mut ConnorMemorySearchKernel {
    match unsafe_string(index_dir).and_then(|path| ConnorMemorySearchKernel::open(path).map_err(|err| err.to_string())) {
        Ok(kernel) => Box::into_raw(Box::new(kernel)),
        Err(message) => {
            set_error(error, message);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_close(handle: *mut ConnorMemorySearchKernel) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle)); }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_rebuild_from_sqlite(
    handle: *mut ConnorMemorySearchKernel,
    database_path: *const c_char,
    limit_per_layer: usize,
    indexed_count: *mut usize,
    error: *mut *mut c_char,
) -> i32 {
    if handle.is_null() {
        set_error(error, "search handle is null");
        return -1;
    }
    let database_path = match unsafe_string(database_path) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let limit = if limit_per_layer == 0 { None } else { Some(limit_per_layer) };
    let kernel = unsafe { &*handle };
    match kernel.rebuild_from_sqlite(database_path, limit) {
        Ok(count) => {
            if !indexed_count.is_null() {
                unsafe { *indexed_count = count; }
            }
            0
        }
        Err(err) => {
            set_error(error, err.to_string());
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_upsert_record(
    handle: *mut ConnorMemorySearchKernel,
    database_path: *const c_char,
    layer: *const c_char,
    record_id: *const c_char,
    upserted: *mut i32,
    error: *mut *mut c_char,
) -> i32 {
    if handle.is_null() {
        set_error(error, "search handle is null");
        return -1;
    }
    let database_path = match unsafe_string(database_path) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let layer = match unsafe_string(layer) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let record_id = match unsafe_string(record_id) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let kernel = unsafe { &*handle };
    match kernel.upsert_record_from_sqlite(database_path, &layer, &record_id) {
        Ok(value) => {
            if !upserted.is_null() {
                unsafe { *upserted = if value { 1 } else { 0 } };
            }
            0
        }
        Err(err) => {
            set_error(error, err.to_string());
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_delete_record(
    handle: *mut ConnorMemorySearchKernel,
    layer: *const c_char,
    record_id: *const c_char,
    error: *mut *mut c_char,
) -> i32 {
    if handle.is_null() {
        set_error(error, "search handle is null");
        return -1;
    }
    let layer = match unsafe_string(layer) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let record_id = match unsafe_string(record_id) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let kernel = unsafe { &*handle };
    match kernel.delete_record(&layer, &record_id) {
        Ok(()) => 0,
        Err(err) => {
            set_error(error, err.to_string());
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_drain_queue(
    handle: *mut ConnorMemorySearchKernel,
    database_path: *const c_char,
    limit: usize,
    upserted_count: *mut usize,
    deleted_count: *mut usize,
    failed_count: *mut usize,
    remaining_count: *mut usize,
    error: *mut *mut c_char,
) -> i32 {
    if handle.is_null() {
        set_error(error, "search handle is null");
        return -1;
    }
    let database_path = match unsafe_string(database_path) {
        Ok(value) => value,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let kernel = unsafe { &*handle };
    match kernel.drain_queue(database_path, limit) {
        Ok(result) => {
            if !upserted_count.is_null() {
                unsafe { *upserted_count = result.upserted; }
            }
            if !deleted_count.is_null() {
                unsafe { *deleted_count = result.deleted; }
            }
            if !failed_count.is_null() {
                unsafe { *failed_count = result.failed; }
            }
            if !remaining_count.is_null() {
                unsafe { *remaining_count = result.remaining; }
            }
            0
        }
        Err(err) => {
            set_error(error, err.to_string());
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_query(
    handle: *mut ConnorMemorySearchKernel,
    request_json: *const c_char,
    result_json: *mut *mut c_char,
    error: *mut *mut c_char,
) -> i32 {
    if handle.is_null() {
        set_error(error, "search handle is null");
        return -1;
    }
    let request = match unsafe_string(request_json).and_then(|json| serde_json::from_str::<MemorySearchRequest>(&json).map_err(|err| err.to_string())) {
        Ok(request) => request,
        Err(message) => {
            set_error(error, message);
            return -1;
        }
    };
    let kernel = unsafe { &*handle };
    match kernel.search(request).and_then(|response| serde_json::to_string(&response).map_err(Into::into)) {
        Ok(json) => {
            unsafe { *result_json = into_c_string(json); }
            0
        }
        Err(err) => {
            set_error(error, err.to_string());
            -1
        }
    }
}

#[no_mangle]
pub extern "C" fn connor_search_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)); }
    }
}

fn unsafe_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("null string pointer".to_string());
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(ToOwned::to_owned)
        .map_err(|err| err.to_string())
}

fn set_error(error: *mut *mut c_char, message: impl Into<String>) {
    if !error.is_null() {
        unsafe { *error = into_c_string(message.into()); }
    }
}

fn into_c_string(value: String) -> *mut c_char {
    CString::new(value).unwrap_or_else(|_| CString::new("invalid string").expect("static string")).into_raw()
}
