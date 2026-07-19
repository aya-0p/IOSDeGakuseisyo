#pragma once

#include <stddef.h>
#include <stdint.h>

namespace nfcf {

// Core NFC normally returns FeliCa command data without LEN. Some older
// transports retain LEN, so both representations are accepted deliberately.
bool ExtractPollingPMmTail(const uint8_t *response, size_t response_length,
                           const uint8_t expected_idm[8],
                           uint8_t pmm_tail[6]);

}  // namespace nfcf
