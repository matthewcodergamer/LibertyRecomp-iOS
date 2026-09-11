#include "liberty/content_provider.hpp"

#include <system_error>

namespace liberty::content {

const std::vector<std::string>& required_game_files() {
    static const std::vector<std::string> files{"default.xex", "common.rpf", "xbox360.rpf", "audio.rpf"};
    return files;
}

ValidationResult GameContentProvider::validate_required_files() const {
    const auto content_layout = layout();
    ValidationResult result;
    for (const auto& relative : required_game_files()) {
        std::error_code error;
        const auto candidate = content_layout.game_root / relative;
        if (!std::filesystem::is_regular_file(candidate, error) || error) {
            result.missing_files.push_back(relative);
        }
    }
    result.ok = result.missing_files.empty();
    return result;
}

EmbeddedContentProvider::EmbeddedContentProvider(std::filesystem::path root) : root_(std::move(root)) {}

ContentLayout EmbeddedContentProvider::layout() const {
    return ContentLayout{.game_root = root_, .dlc_root = root_ / "dlc", .cache_root = root_ / ".liberty-cache", .config_root = root_ / ".liberty-config", .saves_root = root_ / ".liberty-saves"};
}

ImportedContentProvider::ImportedContentProvider(std::filesystem::path application_support_root, std::filesystem::path documents_root)
    : application_support_root_(std::move(application_support_root)), documents_root_(std::move(documents_root)) {}

ContentLayout ImportedContentProvider::layout() const {
    const auto base = application_support_root_ / "LibertyRecomp";
    return ContentLayout{.game_root = base / "Game", .dlc_root = base / "DLC", .cache_root = base / "Cache", .config_root = base / "Config", .saves_root = documents_root_ / "LibertyRecomp" / "saves"};
}

void ImportedContentProvider::ensure_layout() const {
    const auto content_layout = layout();
    std::error_code error;
    std::filesystem::create_directories(content_layout.dlc_root, error);
    if (error) throw std::filesystem::filesystem_error("Failed to create DLC directory", content_layout.dlc_root, error);
    std::filesystem::create_directories(content_layout.cache_root, error);
    if (error) throw std::filesystem::filesystem_error("Failed to create cache directory", content_layout.cache_root, error);
    std::filesystem::create_directories(content_layout.config_root, error);
    if (error) throw std::filesystem::filesystem_error("Failed to create config directory", content_layout.config_root, error);
    std::filesystem::create_directories(content_layout.saves_root, error);
    if (error) throw std::filesystem::filesystem_error("Failed to create saves directory", content_layout.saves_root, error);
}

} // namespace liberty::content
