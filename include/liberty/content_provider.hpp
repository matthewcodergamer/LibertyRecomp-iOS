#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace liberty::content {

struct ContentLayout {
    std::filesystem::path game_root;
    std::filesystem::path dlc_root;
    std::filesystem::path cache_root;
    std::filesystem::path config_root;
    std::filesystem::path saves_root;
};

struct ValidationResult {
    bool ok{false};
    std::vector<std::string> missing_files;
};

class GameContentProvider {
public:
    virtual ~GameContentProvider() = default;
    [[nodiscard]] virtual ContentLayout layout() const = 0;
    [[nodiscard]] ValidationResult validate_required_files() const;
};

class EmbeddedContentProvider final : public GameContentProvider {
public:
    explicit EmbeddedContentProvider(std::filesystem::path root);
    [[nodiscard]] ContentLayout layout() const override;
private:
    std::filesystem::path root_;
};

class ImportedContentProvider final : public GameContentProvider {
public:
    ImportedContentProvider(std::filesystem::path application_support_root, std::filesystem::path documents_root);
    [[nodiscard]] ContentLayout layout() const override;
    void ensure_layout() const;
private:
    std::filesystem::path application_support_root_;
    std::filesystem::path documents_root_;
};

[[nodiscard]] const std::vector<std::string>& required_game_files();

} // namespace liberty::content
