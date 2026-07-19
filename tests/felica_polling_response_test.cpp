#include "FeliCaPollingResponse.hpp"

#include <assert.h>
#include <string.h>

int main() {
    const uint8_t idm[8] = {0x01, 0x23, 0x45, 0x67,
                            0x89, 0xab, 0xcd, 0xef};
    const uint8_t pmm[8] = {0xfe, 0xfe, 0x10, 0x20,
                            0x30, 0x40, 0x50, 0x60};
    uint8_t response[19] = {0x01};
    memcpy(response + 1, idm, sizeof(idm));
    memcpy(response + 9, pmm, sizeof(pmm));
    response[17] = 0xfe;
    response[18] = 0x00;

    uint8_t tail[6] = {};
    assert(nfcf::ExtractPollingPMmTail(response, sizeof(response), idm, tail));
    assert(memcmp(tail, pmm + 2, sizeof(tail)) == 0);

    uint8_t response_with_length[20] = {};
    response_with_length[0] = sizeof(response_with_length);
    memcpy(response_with_length + 1, response, sizeof(response));
    memset(tail, 0, sizeof(tail));
    assert(nfcf::ExtractPollingPMmTail(response_with_length,
                                      sizeof(response_with_length), idm, tail));
    assert(memcmp(tail, pmm + 2, sizeof(tail)) == 0);

    uint8_t malformed[sizeof(response)] = {};
    memcpy(malformed, response, sizeof(response));
    malformed[0] = 0x02;
    assert(!nfcf::ExtractPollingPMmTail(malformed, sizeof(malformed), idm, tail));
    malformed[0] = 0x01;
    malformed[1] ^= 0xff;
    assert(!nfcf::ExtractPollingPMmTail(malformed, sizeof(malformed), idm, tail));
    memcpy(malformed, response, sizeof(response));
    malformed[18] = 0xff;
    assert(!nfcf::ExtractPollingPMmTail(malformed, sizeof(malformed), idm, tail));
    assert(!nfcf::ExtractPollingPMmTail(response, 16, idm, tail));
    assert(!nfcf::ExtractPollingPMmTail(nullptr, sizeof(response), idm, tail));
    return 0;
}
