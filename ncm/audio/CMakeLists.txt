cmake_minimum_required(VERSION 3.21)
project(ncm_audio VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# NCM Audio (NCM FX, 2026-10-12): the continuous sound of NCM's physics. miniaudio and stb_vorbis (public domain /
# MIT-0) come from NCM Radio's third_party; the SDK and nlohmann/json from the carrier's tree. It shares no code,
# state, port range or package with any other NCM plugin.
set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party")
set(AUDIO_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/../radio/third_party")
if (NOT EXISTS "${DEPS_ROOT}/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise ncm/carrier/third_party first.")
endif()
if (NOT EXISTS "${DEPS_ROOT}/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run ncm/carrier/fetch-deps.ps1 first.")
endif()

add_subdirectory("${DEPS_ROOT}/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_audio SHARED
    src/main.cpp
    src/log.cpp
    src/bridge.cpp
    src/mixer.cpp
    src/miniaudio_impl.cpp
)
target_include_directories(ncm_audio PRIVATE src "${AUDIO_DEPS}" "${DEPS_ROOT}/json")
target_link_libraries(ncm_audio PRIVATE RED4ext.SDK ws2_32 iphlpapi)
target_compile_definitions(ncm_audio PRIVATE
    NCM_AUDIO_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_audio PROPERTIES OUTPUT_NAME "ncm_audio" PREFIX "")
if (MSVC)
    target_compile_options(ncm_audio PRIVATE /EHsc /permissive-)
    set_source_files_properties(src/miniaudio_impl.cpp PROPERTIES COMPILE_OPTIONS "/W0")
    set_source_files_properties(src/main.cpp src/log.cpp src/bridge.cpp src/mixer.cpp PROPERTIES COMPILE_OPTIONS "/W4")
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(ncm_audio_math_tests tests/math_tests.cpp)
    target_include_directories(ncm_audio_math_tests PRIVATE src)
    add_test(NAME ncm_audio_math COMMAND ncm_audio_math_tests)
    add_executable(ncm_audio_smoke tests/mixer_smoke.cpp src/mixer.cpp src/log.cpp src/miniaudio_impl.cpp)
    target_include_directories(ncm_audio_smoke PRIVATE src "${AUDIO_DEPS}" "${DEPS_ROOT}/json")
    target_compile_definitions(ncm_audio_smoke PRIVATE NCM_AUDIO_VERSION="${PROJECT_VERSION}" WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
    add_test(NAME ncm_audio_smoke COMMAND ncm_audio_smoke "${CMAKE_CURRENT_SOURCE_DIR}")
endif()
