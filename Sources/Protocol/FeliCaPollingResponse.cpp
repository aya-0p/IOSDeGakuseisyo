#include "FeliCaPollingResponse.hpp"

#include <string.h>

namespace nfcf {

bool ExtractPollingPMmTail(const uint8_t *response, size_t response_length,
                           const uint8_t expected_idm[8],
                           uint8_t pmm_tail[6]) {
    if (response == nullptr || expected_idm == nullptr || pmm_tail == nullptr) {
        return false;
    }
    size_t offset = 0;
    if (response_length == 19 && response[0] == 0x01) {
        offset = 0;
    } else if (response_length == 20 && response[0] == response_length &&
               response[1] == 0x01) {
        offset = 1;
    } else {
        return false;
    }
    if (memcmp(response + offset + 1, expected_idm, 8) != 0 ||
        response[offset + 17] != 0xfe || response[offset + 18] != 0x00) {
        return false;
    }
    memcpy(pmm_tail, response + offset + 11, 6);
    return true;
}

}  // namespace nfcf
