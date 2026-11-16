#include "../Sources/Protocol/NFCFProfileRecord.hpp"

#include <assert.h>
#include <string.h>

int main() {
    nfcf::Profile profile = {};
    profile.system_code = 0x048b;
    profile.service_code = 0x200b;
    const uint8_t idm[8] = {
        0x01, 0xfe, 0x00, 0x10, 0x20, 0x30, 0x40, 0x50,
    };
    const uint8_t pmm[6] = {
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66,
    };
    const uint8_t blocks[nfcf::kMaximumBlockCount][nfcf::kBlockSize] = {
        {'L', '1', 'T', 'E', 'S', 'T'},
        {'T', 'E', 'S', 'T', ' ', 'U', 'S', 'E', 'R'},
        {'T', 'E', 'S', 'T', '-', 'O', 'R', 'G'},
        {'T', 'E', 'S', 'T', '-', 'N', 'U', 'M'},
    };
    memcpy(profile.idm, idm, sizeof(idm));
    memcpy(profile.pmm_tail, pmm, sizeof(pmm));
    profile.block_count = nfcf::kMaximumBlockCount;
    memcpy(profile.blocks, blocks, sizeof(blocks));

    nfcf::ProfileRecord record = {};
    assert(nfcf::MakeProfileRecord(profile, &record));
    assert(nfcf::IsProfileRecordFormat(record));

    uint8_t encoded[nfcf::kProfileRecordEncodedSize] = {};
    assert(nfcf::EncodeProfileRecord(record, encoded, sizeof(encoded)));
    assert(sizeof(encoded) == 99);
    assert(memcmp(encoded, "NFCFPROF", 8) == 0);
    assert(encoded[8] == 1 && encoded[9] == 0);
    assert(encoded[12] == 0x8b && encoded[13] == 0x04);
    assert(encoded[14] == 0x0b && encoded[15] == 0x20);
    assert(encoded[30] == nfcf::kMaximumBlockCount);

    nfcf::ProfileRecord decoded = {};
    assert(nfcf::DecodeProfileRecordBytes(encoded, sizeof(encoded), &decoded));
    nfcf::Profile round_trip = {};
    assert(nfcf::DecodeProfileRecord(decoded, &round_trip));
    assert(round_trip.system_code == profile.system_code);
    assert(round_trip.service_code == profile.service_code);
    assert(round_trip.block_count == profile.block_count);
    assert(memcmp(round_trip.idm, profile.idm, sizeof(profile.idm)) == 0);
    assert(memcmp(round_trip.pmm_tail, profile.pmm_tail,
                  sizeof(profile.pmm_tail)) == 0);
    assert(memcmp(round_trip.blocks, profile.blocks,
                  sizeof(profile.blocks)) == 0);

    encoded[40] ^= 1;
    assert(!nfcf::DecodeProfileRecordBytes(encoded, sizeof(encoded), &decoded));
    profile.block_count = 0;
    assert(!nfcf::MakeProfileRecord(profile, &record));
    return 0;
}
