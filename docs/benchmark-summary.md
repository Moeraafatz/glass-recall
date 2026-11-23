### Measured Benchmarks (Apple Silicon (arm64) · Version 26.7.2 (Build 25G332))

- **Frame-Diff Gate:** `0.10 ms` avg evaluation · `80.0%` static frames dropped before OCR
- **Apple Vision OCR:** `750.6 ms` avg per changed 1280×800 frame · `100.0%` verified token recall
- **Secret Redactor:** `0.28 ms` avg · `4/4` injected credential types scrubbed
- **30-Day Storage (47,520 memories):** **`48.4 MB`** vs `64.2 GB` raw PNG (**`1357x` smaller**)

| Indexed Memories | SQLite WAL Size | Bytes / Memory | Hybrid Search p50 | Hybrid Search p95 |
| ---: | ---: | ---: | ---: | ---: |
| 1000 | 1.09 MB | 1143 B | **4.78 ms** | **5.67 ms** |
| 5000 | 5.09 MB | 1067 B | **6.91 ms** | **15.77 ms** |
| 10000 | 10.02 MB | 1050 B | **8.04 ms** | **10.59 ms** |
| 25000 | 25.48 MB | 1069 B | **16.11 ms** | **20.91 ms** |
