# Upstream integration

`LibertyRecomp-iOS` does not copy the LibertyRecomp source tree into this repository. Instead, it pins one exact upstream commit in [`UPSTREAM.lock`](../UPSTREAM.lock) and checks that revision out when an upstream reference build is needed.

Current upstream:

- Repository: `https://github.com/matthewcodergamer/LibertyRecomp.git`
- Commit: `38a6dbcc33b5040524a32966a3c9ffcbcf5d5f72`
- Commit message: `checkpoint: renderer and gameplay state before performance rewrite`

This keeps the iOS project reproducible while preserving upstream history.

## Fetching the pinned source

```bash
./scripts/fetch-upstream.sh
```

The default checkout is `.cache/LibertyRecomp/`, which is ignored by Git. To initialize all upstream submodules as well:

```bash
./scripts/fetch-upstream.sh --recursive
```

A custom destination may be supplied:

```bash
./scripts/fetch-upstream.sh --destination /path/to/LibertyRecomp
```

The script verifies that the checked-out `HEAD` exactly equals the SHA in `UPSTREAM.lock`.

## Updating the pin

Do not silently follow upstream `main`.

1. Choose an upstream commit deliberately.
2. Review upstream changes, especially ReXGlue, RAGE patches, renderer, iOS files, shader tooling, and build-system changes.
3. Update only the `commit` and descriptive `note` in `UPSTREAM.lock`.
4. Run:
   ```bash
   ./scripts/fetch-upstream.sh --destination .cache/LibertyRecomp
   cmake --preset host-debug
   cmake --build --preset host-debug
   ctest --preset host-debug
   ```
5. Run the Apple CI jobs.
6. Only after the pin is proven should later runtime integration work be based on it.

## Reference-build policy

The native iOS shell in this repository is deliberately buildable without GTA IV data. The upstream reference source is fetched separately. A complete GTA IV reference run still requires a legally owned game copy and is not performed in public CI.

Public CI may compile or configure only code that can be built without copyrighted game files. No `default.xex`, RPF archives, title updates, keys, or generated proprietary game payloads are uploaded as artifacts.
