#include "IndividualProgressionTalent.h"

#include "Chat.h"
#include "DatabaseEnv.h"
#include "Field.h"
#include "IndividualProgression.h"
#include "Player.h"
#include "QueryResult.h"
#include "WorldSession.h"

#include <algorithm>
#include <charconv>
#include <cctype>
#include <string>
#include <unordered_set>
#include <vector>

namespace
{
bool IsManaged(Player* player,
               IndividualProgressionTalent::TalentTables& tables)
{
    if (!IndividualProgressionTalent::ResolveTables(player, tables))
        return false;
    QueryResult result = WorldDatabase.Query(
        "SELECT 1 FROM {} WHERE classId={} LIMIT 1",
        tables.definitions, player->getClass());
    return bool(result);
}

void SendAddon(Player* player, std::string const& payload)
{
    std::string message = "IPTAL\t" + payload;
    WorldPacket packet;
    ChatHandler::BuildChatPacket(packet, CHAT_MSG_WHISPER, LANG_ADDON,
                                 player, player, message);
    player->GetSession()->SendPacket(&packet);
}

void SendSnapshot(Player* player)
{
    IndividualProgressionTalent::TalentTables tables{};
    bool managed = IsManaged(player, tables);
    uint8 era = sIndividualProgression->GetPlayerProgressionFromQuests(player)
        <= PROGRESSION_NAXX40 ? 0 : 1;
    if (!managed)
    {
        SendAddon(player, "SYNC " + std::to_string(era) + " 0 0");
        return;
    }

    uint32 pointCap = era == 0 ? 51 : 61;
    uint32 earned = player->GetLevel() > 9 ? player->GetLevel() - 9 : 0;
    uint32 spent = 0;
    std::vector<std::string> ranks;
    std::unordered_set<uint32> validTalents;
    QueryResult definitions = WorldDatabase.Query(
        "SELECT id FROM {} WHERE classId={}",
        tables.definitions, player->getClass());
    if (definitions)
        do
        {
            validTalents.insert((*definitions)[0].Get<uint32>());
        } while (definitions->NextRow());

    QueryResult result = CharacterDatabase.Query(
        "SELECT talentId,`rank` FROM {} WHERE guid={}",
        tables.characters, player->GetGUID().GetCounter());
    if (result)
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 id = fields[0].Get<uint32>();
            uint8 rank = fields[1].Get<uint8>();
            if (validTalents.find(id) == validTalents.end())
                continue;
            spent += rank;
            ranks.push_back(std::to_string(id) + ":" +
                            std::to_string(rank));
        } while (result->NextRow());
    }

    uint32 available = std::min(earned, pointCap);
    available = spent >= available ? 0 : available - spent;
    std::vector<std::string> chunks(1);
    for (std::string const& entry : ranks)
    {
        size_t separator = chunks.back().empty() ? 0 : 1;
        if (chunks.back().size() + separator + entry.size() > 150)
            chunks.emplace_back();
        if (!chunks.back().empty())
            chunks.back() += ',';
        chunks.back() += entry;
    }
    for (size_t i = 0; i < chunks.size(); ++i)
        SendAddon(player, "SYNC " + std::to_string(era) + " 1 " +
            std::to_string(available) + " " + std::to_string(i + 1) + "/" +
            std::to_string(chunks.size()) + " " + chunks[i]);
}

bool HandleProtocol(Player* player, std::string& message)
{
    constexpr char prefix[] = "IPTAL\t";
    if (message.compare(0, sizeof(prefix) - 1, prefix) != 0)
        return false;

    std::string command = message.substr(sizeof(prefix) - 1);
    if (command == "HELLO")
        SendSnapshot(player);
    else if (command.rfind("LEARN ", 0) == 0)
    {
        std::string idText = command.substr(6);
        if (idText.empty() || idText.size() > 10 ||
            !std::all_of(idText.begin(), idText.end(),
                         [](unsigned char c) { return std::isdigit(c); }))
            return true;

        uint32 talentId = 0;
        auto parsed = std::from_chars(idText.data(),
                                      idText.data() + idText.size(),
                                      talentId);
        if (parsed.ec != std::errc{} ||
            parsed.ptr != idText.data() + idText.size())
            return true;

        std::string error;
        if (IndividualProgressionTalent::LearnNextRank(
                player, talentId, error))
            IndividualProgressionTalent::Reconcile(player);
        SendSnapshot(player);
    }
    return true;
}
}

class IndividualProgressionTalentProtocolScript : public PlayerScript
{
public:
    IndividualProgressionTalentProtocolScript()
        : PlayerScript("IndividualProgressionTalentProtocolScript")
    {
    }

    bool OnPlayerCanUseChat(Player* player, uint32 type, uint32 language,
                            std::string& message, Player* receiver) override
    {
        if (type == CHAT_MSG_WHISPER && language == LANG_ADDON &&
            receiver == player && HandleProtocol(player, message))
            return false;
        return true;
    }
};

void AddSC_individualProgression_talent_protocol()
{
    new IndividualProgressionTalentProtocolScript();
}
