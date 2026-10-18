#include "IndividualProgressionTalent.h"

#include "DatabaseEnv.h"
#include "Field.h"
#include "Player.h"
#include "QueryResult.h"
#include "IndividualProgression.h"

#include <vector>

namespace
{
using Services = std::vector<IndividualProgressionTalent::Service>;

Services& GetServices()
{
    static Services services;
    return services;
}

IndividualProgressionTalent::Service const* FindService(
    uint8 classId)
{
    for (auto const& service : GetServices())
        if (service.classId == classId)
            return &service;
    return nullptr;
}

IndividualProgressionTalent::Service const* FindTalentService(
    Player* player, uint32 talentId)
{
    IndividualProgressionTalent::TalentTables tables{};
    if (!IndividualProgressionTalent::ResolveTables(player, tables))
        return nullptr;
    QueryResult result = WorldDatabase.Query(
        "SELECT classId FROM {} WHERE id={}", tables.definitions,
        talentId);
    if (!result)
        return nullptr;

    return FindService((*result)[0].Get<uint8>());
}

}

namespace IndividualProgressionTalent
{
bool ResolveTables(Player* player, TalentTables& tables)
{
    if (!player || !player->IsInWorld())
        return false;
    uint8 progression = sIndividualProgression->
        GetPlayerProgressionFromQuests(player);
    if (progression <= PROGRESSION_NAXX40)
        tables = {"vanilla_talent", "vanilla_talent_rank",
                  "vanilla_character_talent", player->getClass()};
    else if (progression <= PROGRESSION_TBC_TIER_4)
        tables = {"tbc_talent", "tbc_talent_rank",
                  "tbc_character_talent", player->getClass()};
    else
        return false;
    return true;
}

void RegisterService(Service const& service)
{
    if (!service.learnNextRank || !service.reset || !service.getRank ||
        !service.reconcile)
        return;

    Services& services = GetServices();
    for (Service& registered : services)
        if (registered.classId == service.classId)
        {
            registered = service;
            return;
        }
    services.push_back(service);
}

bool LearnNextRank(Player* player, uint32 talentId, std::string& error)
{
    Service const* service = FindTalentService(player, talentId);
    if (!service)
    {
        error = "No server talent service is registered for this node.";
        return false;
    }
    return service->learnNextRank(player, talentId, error);
}

bool Reset(Player* player, uint32 talentId)
{
    Service const* service = FindTalentService(player, talentId);
    return service && service->reset(player, talentId);
}

unsigned GetRank(Player* player, uint32 talentId)
{
    Service const* service = FindTalentService(player, talentId);
    return service ? service->getRank(player, talentId) : 0;
}

void Reconcile(Player* player)
{
    if (!player)
        return;

    for (Service const& service : GetServices())
        if (service.classId == player->getClass())
            service.reconcile(player);
}
}

class IndividualProgressionTalentPlayerScript : public PlayerScript
{
public:
    IndividualProgressionTalentPlayerScript()
        : PlayerScript("IndividualProgressionTalentPlayerScript")
    {
    }

    void OnPlayerLogin(Player* player) override
    {
        IndividualProgressionTalent::Reconcile(player);
    }

    bool OnPlayerCanLearnTalent(Player* player, TalentEntry const*,
                                uint32) override
    {
        if (!player || !player->IsInWorld())
            return true;
        if (player->getClass() == CLASS_DEATH_KNIGHT)
            return true;
        IndividualProgressionTalent::TalentTables tables{};
        if (!IndividualProgressionTalent::ResolveTables(player, tables))
            return true;

        // The installed class/era definitions determine where the native
        // talent system is fenced. This keeps implementation code independent
        // of the currently imported class data.
        QueryResult definitions = WorldDatabase.Query(
            "SELECT 1 FROM {} WHERE classId={} LIMIT 1",
            tables.definitions, player->getClass());
        return !definitions;
    }
};

void AddSC_individualProgression_talent()
{
    new IndividualProgressionTalentPlayerScript();
}
