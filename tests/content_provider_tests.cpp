#include "liberty/content_provider.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace fs = std::filesystem;
static int failures = 0;

void expect(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

int main() {
    const auto base = fs::temp_directory_path() / "libertyrecomp-ios-content-provider-test";
    std::error_code ignored;
    fs::remove_all(base, ignored);
    fs::create_directories(base / "app-support");
    fs::create_directories(base / "documents");

    liberty::content::ImportedContentProvider imported{base / "app-support", base / "documents"};
    imported.ensure_layout();
    const auto layout = imported.layout();
    expect(fs::is_directory(layout.dlc_root), "DLC directory should exist");
    expect(fs::is_directory(layout.cache_root), "Cache directory should exist");
    expect(fs::is_directory(layout.config_root), "Config directory should exist");
    expect(fs::is_directory(layout.saves_root), "Saves directory should exist");

    auto result = imported.validate_required_files();
    expect(!result.ok, "Empty game directory must not validate");
    expect(result.missing_files.size() == 4, "All four required files should be missing");

    fs::create_directories(layout.game_root);
    for (const auto& name : liberty::content::required_game_files()) std::ofstream(layout.game_root / name) << "dummy";
    result = imported.validate_required_files();
    expect(result.ok, "Dummy required files should satisfy structural validation");
    expect(result.missing_files.empty(), "No required file should be reported missing");

    fs::remove_all(base, ignored);
    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "content_provider_tests: PASS\n";
    return 0;
}
