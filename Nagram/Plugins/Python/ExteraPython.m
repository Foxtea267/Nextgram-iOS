#import "ExteraPython.h"
#include <Python/Python.h>

static NSString *errorResponse(NSString *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"error": message} options:0 error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSString *pythonError(void) {
    PyObject *type = NULL, *value = NULL, *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyObject *description = value ? PyObject_Str(value) : NULL;
    const char *utf8 = description ? PyUnicode_AsUTF8(description) : NULL;
    NSString *message = utf8 ? [NSString stringWithUTF8String:utf8] : @"Python bridge failed.";
    Py_XDECREF(description);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    PyErr_Clear();
    return errorResponse(message ?: @"Python bridge failed.");
}

static NSString *NagramExteraRun(NSString *stdlibPath, NSString *bootstrap, NSString *request) {
    static NSString *startupError;
    static PyObject *dispatcher;
    if (startupError != nil) {
        return startupError;
    }
    if (!Py_IsInitialized()) {
        PyPreConfig preconfig;
        PyPreConfig_InitIsolatedConfig(&preconfig);
        preconfig.utf8_mode = 1;
        PyStatus status = Py_PreInitialize(&preconfig);
        if (PyStatus_Exception(status)) {
            startupError = errorResponse(@"Python preinitialization failed.");
            return startupError;
        }
        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.site_import = 0;
        config.write_bytecode = 0;
        config.install_signal_handlers = 0;
        config.module_search_paths_set = 1;
        wchar_t *path = Py_DecodeLocale(stdlibPath.fileSystemRepresentation, NULL);
        if (path == NULL) {
            PyConfig_Clear(&config);
            startupError = errorResponse(@"Cannot read the Python standard library path.");
            return startupError;
        }
        status = PyWideStringList_Append(&config.module_search_paths, path);
        PyMem_RawFree(path);
        if (!PyStatus_Exception(status)) {
            status = Py_InitializeFromConfig(&config);
        }
        PyConfig_Clear(&config);
        if (PyStatus_Exception(status)) {
            startupError = errorResponse(status.err_msg ? [NSString stringWithUTF8String:status.err_msg] : @"Python initialization failed.");
            return startupError;
        }
        PyEval_SaveThread();
    }

    PyGILState_STATE gil = PyGILState_Ensure();
    NSString *result;
    if (dispatcher == NULL) {
        PyObject *globals = PyModule_GetDict(PyImport_AddModule("__main__"));
        PyObject *loaded = PyRun_String(bootstrap.UTF8String, Py_file_input, globals, globals);
        if (loaded != NULL) {
            Py_DECREF(loaded);
            dispatcher = Py_XNewRef(PyDict_GetItemString(globals, "dispatch_json"));
        }
        if (dispatcher == NULL) {
            startupError = pythonError();
            PyGILState_Release(gil);
            return startupError;
        }
    }
    PyObject *response = PyObject_CallFunction(dispatcher, "s", request.UTF8String);
    const char *utf8 = response ? PyUnicode_AsUTF8(response) : NULL;
    result = utf8 ? [NSString stringWithUTF8String:utf8] : pythonError();
    Py_XDECREF(response);
    PyGILState_Release(gil);
    return result;
}

@interface NextgramExteraPythonHost : NSObject <NagramExteraPythonHost>
@end

@implementation NextgramExteraPythonHost
+ (NSString *)runWithStdlibPath:(NSString *)stdlibPath bootstrap:(NSString *)bootstrap request:(NSString *)request {
    return NagramExteraRun(stdlibPath, bootstrap, request);
}
@end
