#ifndef INDIVIDUAL_PROGRESSION_TALENT_H
#define INDIVIDUAL_PROGRESSION_TALENT_H

#include "Define.h"

#include <string>

class Player;

namespace IndividualProgressionTalent
{
    struct TalentTables
    {
        char const* definitions;
        char const* ranks;
        char const* characters;
        uint8 classId;
    };

    bool ResolveTables(Player* player, TalentTables& tables);
    struct Service
    {
        uint8 classId;
        bool (*learnNextRank)(Player*, uint32, std::string&);
        bool (*reset)(Player*, uint32);
        unsigned (*getRank)(Player*, uint32);
        void (*reconcile)(Player*);
    };

    void RegisterService(Service const& service);
    bool LearnNextRank(Player* player, uint32 talentId, std::string& error);
    bool Reset(Player* player, uint32 talentId);
    void Reconcile(Player* player);
    unsigned GetRank(Player* player, uint32 talentId);
}

#endif
