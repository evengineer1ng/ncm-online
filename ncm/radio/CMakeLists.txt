cmake_minimum_required(VERSION 3.21)
project(ncm_radio VERSION 0.1.2 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Third-party: RED4ext.SDK and nlohmann/json are vendored under the carrier's tree (headers only; nothing of the
# Carrier's is shared). miniaudio and stb_vorbis are public domain (or MIT-0 / MIT), vendored in third_party/.
set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party")
if (NOT EXISTS "${DEPS_ROOT}/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise ncm/carrier/third_party first.")
endif()
if (NOT EXISTS "${DEPS_ROOT}/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run .\\ncm\\carrier\\fetch-deps.ps1 first.")
endif()

add_subdirectory("${DEPS_ROOT}/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_radio SHARED
    src/main.cpp
    src/log.cpp
    src/bridge.cpp
    src/player.cpp
    src/natives.cpp
    src/audio_impl.cpp
)

target_include_directories(ncm_radio PRIVATE src third_party "${DEPS_ROOT}/json")
target_link_libraries(ncm_radio PRIVATE RED4ext.SDK ws2_32 iphlpapi)
target_compile_definitions(ncm_radio PRIVATE
    NCM_RADIO_VERSION="${PROJECT_VERSION}"
    NCM_RADIO_MAJOR=${PROJECT_VERSION_MAJOR} NCM_RADIO_MINOR=${PROJECT_VERSION_MINOR} NCM_RADIO_PATCH=${PROJECT_VERSION_PATCH}
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_radio PROPERTIES OUTPUT_NAME "ncm_radio" PREFIX "")

if (MSVC)
    target_compile_options(ncm_radio PRIVATE /W4 /EHsc /permissive-)
    # third-party single-file libraries are not ours to warn about
    set_source_files_properties(src/audio_impl.cpp PROPERTIES COMPILE_OPTIONS "/W0")
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(ncm_radio_timeline_tests tests/timeline_tests.cpp)
    target_include_directories(ncm_radio_timeline_tests PRIVATE src)
    add_test(NAME ncm_radio_timeline COMMAND ncm_radio_timeline_tests)
endif()
