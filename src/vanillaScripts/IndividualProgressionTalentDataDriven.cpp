#include "IndividualProgressionTalent.h"

#include "DatabaseEnv.h"
#include "Field.h"
#include "IndividualProgression.h"
#include "Player.h"
#include "QueryResult.h"
#include "SpellMgr.h"

#include <algorithm>
#include <unordered_map>
#include <vector>

namespace
{
constexpr uint8 VANILLA_POINT_CAP = 51;

IndividualProgressionTalent::TalentTables GetTables(Player* player)
{
    IndividualProgressionTalent::TalentTables tables{};
    IndividualProgressionTalent::ResolveTables(player, tables);
    return tables;
}

struct TalentNode
{
    uint8 tab;
    uint8 maxRank;
    uint32 prerequisiteId;
    uint8 prerequisitePoints;
};

using TalentTrees = std::unordered_map<uint32, uint8>;
TalentTrees LoadTalentTrees(Player* player)
{
    TalentTrees trees;
    QueryResult result = WorldDatabase.Query(
        "SELECT id, tab FROM {} WHERE classId={}",
        GetTables(player).definitions, player->getClass());
    if (!result)
        return trees;
    do
    {
        Field* fields = result->Fetch();
        trees[fields[0].Get<uint32>()] = fields[1].Get<uint8>();
    } while (result->NextRow());
    return trees;
}

unsigned LoadSpentPointsInTree(Player* player, uint8 tab)
{
    TalentTrees trees = LoadTalentTrees(player);
    QueryResult result = CharacterDatabase.Query(
        "SELECT talentId, `rank` FROM {} WHERE guid={}",
        GetTables(player).characters, player->GetGUID().GetCounter());
    unsigned spent = 0;
    if (!result)
        return spent;
    do
    {
        Field* fields = result->Fetch();
        auto itr = trees.find(fields[0].Get<uint32>());
        if (itr != trees.end() && itr->second == tab)
            spent += fields[1].Get<uint8>();
    } while (result->NextRow());
    return spent;
}

using RankSpells = std::vector<uint32>;

bool IsManagedEra(Player* player)
{
    IndividualProgressionTalent::TalentTables tables{};
    return IndividualProgressionTalent::ResolveTables(player, tables);
}

bool LoadNode(Player* player, uint32 talentId, TalentNode& node)
{
    auto tables = GetTables(player);
    QueryResult result = WorldDatabase.Query(
        "SELECT tab, maxRank, prereqTalentId, prereqPoints FROM {} "
        "WHERE id={} AND classId={}",
        tables.definitions, talentId, player->getClass());
    if (!result)
        return false;

    Field* fields = result->Fetch();
    node.tab = fields[0].Get<uint8>();
    node.maxRank = fields[1].Get<uint8>();
    node.prerequisiteId = fields[2].Get<uint32>();
    node.prerequisitePoints = fields[3].Get<uint8>();
    return node.maxRank != 0;
}

bool LoadRankSpells(Player* player, uint32 talentId, uint8 maxRank,
                    RankSpells& spells)
{
    auto tables = GetTables(player);
    spells.clear();
    QueryResult result = WorldDatabase.Query(
        "SELECT `rank`, grantedSpellId FROM {} "
        "WHERE talentId={} ORDER BY `rank`", tables.ranks, talentId);
    if (!result)
        return false;

    uint8 expectedRank = 1;
    do
    {
        Field* fields = result->Fetch();
        uint8 rank = fields[0].Get<uint8>();
        uint32 spellId = fields[1].Get<uint32>();
        if (rank != expectedRank || rank > maxRank ||
            !sSpellMgr->GetSpellInfo(spellId))
            return false;
        spells.push_back(spellId);
        ++expectedRank;
    } while (result->NextRow());

    return spells.size() == maxRank;
}

unsigned LoadRank(Player* player, uint32 talentId)
{
    auto tables = GetTables(player);
    QueryResult result = CharacterDatabase.Query(
        "SELECT `rank` FROM {} WHERE guid={} AND talentId={}",
        tables.characters, player->GetGUID().GetCounter(), talentId);
    return result ? (*result)[0].Get<uint8>() : 0;
}

unsigned LoadSpentPoints(Player* player)
{
    auto tables = GetTables(player);
    QueryResult result = CharacterDatabase.Query(
        "SELECT COALESCE(SUM(`rank`), 0) FROM {} WHERE guid={}",
        tables.characters, player->GetGUID().GetCounter());
    return result ? (*result)[0].Get<uint32>() : 0;
}

void RemoveCarrierSpells(Player* player, RankSpells const& spells)
{
    for (uint32 spellId : spells)
        if (player->HasSpell(spellId))
            player->removeSpell(spellId, SPEC_MASK_ALL, false);
}

void RemoveAllOwnedSpells(Player* player, char const* rankTable,
                          char const* talentTable)
{
    QueryResult spells = WorldDatabase.Query(
        "SELECT r.grantedSpellId FROM {} r INNER JOIN {} t "
        "ON t.id=r.talentId WHERE t.classId={}",
        rankTable, talentTable, player->getClass());
    if (!spells)
        return;
    do
    {
        uint32 spellId = (*spells)[0].Get<uint32>();
        if (player->HasSpell(spellId))
            player->removeSpell(spellId, SPEC_MASK_ALL, false);
    } while (spells->NextRow());
}

}

namespace IndividualProgressionTalent::DataDriven
{
bool LearnTalent(Player* player, uint32 talentId, std::string& error)
{
    if (!player || !player->IsInWorld())
    {
        error = "You must be logged in to learn this talent.";
        return false;
    }
    if (!IsManagedEra(player))
    {
        error = "Era talents are unavailable at this progression tier.";
        return false;
    }
    if (player->GetLevel() < 10)
    {
        error = "Talent points are available starting at level 10.";
        return false;
    }

    TalentNode node{};
    if (!LoadNode(player, talentId, node))
    {
        error = "Talent data is not installed for this class and era.";
        return false;
    }

    unsigned rank = LoadRank(player, talentId);
    if (rank >= node.maxRank)
    {
        error = "This talent is already at maximum rank.";
        return false;
    }

    unsigned pointCap = VANILLA_POINT_CAP;
    if (sIndividualProgression->GetPlayerProgressionFromQuests(player) >=
        PROGRESSION_PRE_TBC)
        pointCap = 61;
    unsigned availablePoints = std::min<unsigned>(player->GetLevel() - 9,
                                                   pointCap);
    if (LoadSpentPoints(player) >= availablePoints)
    {
        error = "You do not have an unspent Vanilla talent point.";
        return false;
    }
    if (node.prerequisitePoints)
    {
        if (LoadSpentPointsInTree(player, node.tab) < node.prerequisitePoints)
        {
            error = "You have not spent enough points in this talent tree.";
            return false;
        }
    }
    if (node.prerequisiteId)
    {
        QueryResult prerequisite = CharacterDatabase.Query(
            "SELECT `rank` FROM {} WHERE guid={} AND talentId={}",
            GetTables(player).characters,
            player->GetGUID().GetCounter(), node.prerequisiteId);
        QueryResult required = WorldDatabase.Query(
            "SELECT maxRank FROM {} WHERE id={}",
            GetTables(player).definitions, node.prerequisiteId);
        if (!prerequisite || !required ||
            (*prerequisite)[0].Get<uint8>() < (*required)[0].Get<uint8>())
        {
            error = "You have not learned the prerequisite talent.";
            return false;
        }
    }

    RankSpells spells;
    if (!LoadRankSpells(player, talentId, node.maxRank, spells))
    {
        error = "Talent rank spell data is incomplete.";
        return false;
    }

    uint8 nextRank = static_cast<uint8>(rank + 1);
    auto tables = GetTables(player);
    CharacterDatabase.DirectExecute(
        "REPLACE INTO {} (guid, talentId, `rank`) VALUES ({}, {}, {})",
        tables.characters, player->GetGUID().GetCounter(), talentId,
        nextRank);
    if (rank)
        player->removeSpell(spells[rank - 1], SPEC_MASK_ALL, false);
    player->learnSpell(spells[nextRank - 1]);
    return true;
}

bool ResetTalent(Player* player, uint32 talentId)
{
    if (!player || !IsManagedEra(player))
        return false;
    TalentNode node{};
    RankSpells spells;
    if (!LoadNode(player, talentId, node) ||
        !LoadRankSpells(player, talentId, node.maxRank, spells))
        return false;

    RemoveCarrierSpells(player, spells);
    auto tables = GetTables(player);
    CharacterDatabase.DirectExecute(
        "DELETE FROM {} WHERE guid={} AND talentId={}",
        tables.characters, player->GetGUID().GetCounter(), talentId);
    return true;
}

unsigned GetTalentRank(Player* player, uint32 talentId)
{
    return player ? LoadRank(player, talentId) : 0;
}

void Reconcile(Player* player)
{
    if (!player || !player->IsInWorld())
        return;

    IndividualProgressionTalent::TalentTables tables{};
    if (!IndividualProgressionTalent::ResolveTables(player, tables))
    {
        RemoveAllOwnedSpells(player, "vanilla_talent_rank", "vanilla_talent");
        RemoveAllOwnedSpells(player, "tbc_talent_rank", "tbc_talent");
        return;
    }
    RemoveAllOwnedSpells(player,
        tables.definitions[0] == 'v' ? "tbc_talent_rank" :
                                       "vanilla_talent_rank",
        tables.definitions[0] == 'v' ? "tbc_talent" : "vanilla_talent");

    QueryResult talents = WorldDatabase.Query(
        "SELECT id, maxRank FROM {} WHERE classId={}",
        tables.definitions, player->getClass());
    if (!talents)
        return;

    do
    {
        Field* fields = talents->Fetch();
        uint32 talentId = fields[0].Get<uint32>();
        uint8 maxRank = fields[1].Get<uint8>();
        RankSpells spells;
        if (!LoadRankSpells(player, talentId, maxRank, spells))
            continue;

        unsigned rank = LoadRank(player, talentId);
        if (!IsManagedEra(player) || rank > maxRank)
        {
            RemoveCarrierSpells(player, spells);
            continue;
        }

        for (unsigned i = 0; i < spells.size(); ++i)
        {
            if (i + 1 == rank && rank)
            {
                if (!player->HasSpell(spells[i]))
                    player->learnSpell(spells[i]);
            }
            else if (player->HasSpell(spells[i]))
                player->removeSpell(spells[i], SPEC_MASK_ALL, false);
        }
    } while (talents->NextRow());
}
}

void AddSC_individualProgressionTalentDataDriven()
{
    for (uint8 classId : {CLASS_WARRIOR, CLASS_PALADIN, CLASS_HUNTER,
                          CLASS_ROGUE, CLASS_PRIEST, CLASS_SHAMAN,
                          CLASS_MAGE, CLASS_WARLOCK, CLASS_DRUID})
        IndividualProgressionTalent::RegisterService({
            classId,
            IndividualProgressionTalent::DataDriven::LearnTalent,
            IndividualProgressionTalent::DataDriven::ResetTalent,
            IndividualProgressionTalent::DataDriven::GetTalentRank,
            IndividualProgressionTalent::DataDriven::Reconcile});
}
