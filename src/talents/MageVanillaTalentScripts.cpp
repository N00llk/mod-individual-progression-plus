#include "Player.h"
#include "ScriptMgr.h"
#include "SpellAuraEffects.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"

namespace
{
constexpr uint32 SPELL_IGNITE_DOT = 12654;
constexpr uint32 SPELL_MASTER_OF_ELEMENTS_ENERGIZE = 29077;
constexpr uint32 SPELL_FIRE_WARD_REFLECT = 928081;
constexpr uint32 SPELL_FROST_WARD_REFLECT = 928082;
constexpr uint32 CUSTOM_MAGE_SPELL_LOW = 920000;
constexpr uint32 CUSTOM_MAGE_SPELL_HIGH = 930000;

class era_ignite : public AuraScript
{
    PrepareAuraScript(era_ignite);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_IGNITE_DOT });
    }

    bool CheckProc(ProcEventInfo& eventInfo)
    {
        DamageInfo* damage = eventInfo.GetDamageInfo();
        return eventInfo.GetActor() && eventInfo.GetProcTarget() && damage &&
            damage->GetSpellInfo() &&
            (damage->GetSchoolMask() & SPELL_SCHOOL_MASK_FIRE) &&
            (eventInfo.GetHitMask() & PROC_HIT_CRITICAL);
    }

    void HandleProc(AuraEffect const* effect, ProcEventInfo& eventInfo)
    {
        PreventDefaultAction();
        SpellInfo const* dot = sSpellMgr->AssertSpellInfo(SPELL_IGNITE_DOT);
        int32 amount = CalculatePct(eventInfo.GetDamageInfo()->GetDamage(),
                                    effect->GetAmount()) /
            dot->GetMaxTicks();
        eventInfo.GetProcTarget()->CastDelayedSpellWithPeriodicAmount(
            eventInfo.GetActor(), SPELL_IGNITE_DOT,
            SPELL_AURA_PERIODIC_DAMAGE, amount);
    }

    void Register() override
    {
        DoCheckProc += AuraCheckProcFn(era_ignite::CheckProc);
        OnEffectProc += AuraEffectProcFn(era_ignite::HandleProc, EFFECT_0,
                                         SPELL_AURA_DUMMY);
    }
};

class era_master_of_elements : public AuraScript
{
    PrepareAuraScript(era_master_of_elements);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_MASTER_OF_ELEMENTS_ENERGIZE });
    }

    bool CheckProc(ProcEventInfo& eventInfo)
    {
        DamageInfo* damage = eventInfo.GetDamageInfo();
        return damage && damage->GetSpellInfo() &&
            (eventInfo.GetHitMask() & PROC_HIT_CRITICAL);
    }

    void HandleProc(AuraEffect const* effect, ProcEventInfo& eventInfo)
    {
        PreventDefaultAction();
        SpellInfo const* spell = eventInfo.GetDamageInfo()->GetSpellInfo();
        Unit* owner = GetTarget();
        int32 manaCost = spell->ManaCost + int32(CalculatePct(
            owner->GetCreateMana(), spell->ManaCostPercentage));
        int32 mana = CalculatePct(manaCost, effect->GetAmount());
        if (mana > 0)
            owner->CastCustomSpell(SPELL_MASTER_OF_ELEMENTS_ENERGIZE,
                SPELLVALUE_BASE_POINT0, mana, owner, true, nullptr, effect);
    }

    void Register() override
    {
        DoCheckProc += AuraCheckProcFn(era_master_of_elements::CheckProc);
        OnEffectProc += AuraEffectProcFn(era_master_of_elements::HandleProc,
                                         EFFECT_0, SPELL_AURA_DUMMY);
    }
};

class era_ward_reflect : public AuraScript
{
    PrepareAuraScript(era_ward_reflect);

    uint32 _reflectSpell = 0;
    int32 _marker = 0;

    bool Load() override
    {
        SpellSchoolMask school = GetSpellInfo()->GetSchoolMask();
        if (school & SPELL_SCHOOL_MASK_FIRE)
        {
            _reflectSpell = SPELL_FIRE_WARD_REFLECT;
            _marker = 2;
        }
        else if (school & SPELL_SCHOOL_MASK_FROST)
        {
            _reflectSpell = SPELL_FROST_WARD_REFLECT;
            _marker = 3;
        }
        return _reflectSpell != 0;
    }

    int32 MarkerAmount(Unit* caster) const
    {
        for (AuraEffect const* effect :
             caster->GetAuraEffectsByType(SPELL_AURA_DUMMY))
        {
            if (effect->GetMiscValue() != _marker)
                continue;
            uint32 spellId = effect->GetSpellInfo()->Id;
            if (spellId >= CUSTOM_MAGE_SPELL_LOW &&
                spellId < CUSTOM_MAGE_SPELL_HIGH)
                return effect->GetAmount();
        }
        return 0;
    }

    void OnApply(AuraEffect const* effect, AuraEffectHandleModes /*mode*/)
    {
        Unit* target = GetTarget();
        int32 amount = MarkerAmount(target);
        if (amount > 0)
            target->CastCustomSpell(target, _reflectSpell, &amount, nullptr,
                                    nullptr, true, nullptr, effect);
    }

    void OnRemove(AuraEffect const* /*effect*/,
                  AuraEffectHandleModes /*mode*/)
    {
        GetTarget()->RemoveAurasDueToSpell(_reflectSpell);
    }

    void Register() override
    {
        OnEffectApply += AuraEffectApplyFn(era_ward_reflect::OnApply, EFFECT_0,
            SPELL_AURA_SCHOOL_ABSORB, AURA_EFFECT_HANDLE_REAL);
        OnEffectRemove += AuraEffectRemoveFn(era_ward_reflect::OnRemove,
            EFFECT_0, SPELL_AURA_SCHOOL_ABSORB, AURA_EFFECT_HANDLE_REAL);
    }
};

class era_mag_cold_snap : public SpellScript
{
    PrepareSpellScript(era_mag_cold_snap);

    bool Load() override
    {
        return GetCaster() && GetCaster()->IsPlayer();
    }

    void HandleDummy(SpellEffIndex /*effectIndex*/)
    {
        Player* caster = GetCaster()->ToPlayer();
        if (!caster)
            return;

        uint32 ownSpell = GetSpellInfo()->Id;
        PlayerSpellMap const& spells = caster->GetSpellMap();
        for (auto const& [spellId, learnedSpell] : spells)
        {
            (void)learnedSpell;
            SpellInfo const* spell = sSpellMgr->AssertSpellInfo(spellId);
            if (spell->SpellFamilyName != SPELLFAMILY_MAGE ||
                !(spell->GetSchoolMask() & SPELL_SCHOOL_MASK_FROST) ||
                spellId == 11958 || spellId == ownSpell ||
                spell->GetRecoveryTime() == 0)
                continue;

            auto cooldown = caster->GetSpellCooldownMap().find(spellId);
            if (cooldown != caster->GetSpellCooldownMap().end() &&
                cooldown->second.needSendToClient)
                caster->RemoveSpellCooldown(spellId, true);
            else
                caster->RemoveSpellCooldown(spellId, false);
        }
    }

    void Register() override
    {
        OnEffectHit += SpellEffectFn(era_mag_cold_snap::HandleDummy, EFFECT_0,
                                     SPELL_EFFECT_DUMMY);
    }
};
}

void AddSC_individualProgression_mage_vanilla_talents()
{
    RegisterSpellScript(era_ignite);
    RegisterSpellScript(era_master_of_elements);
    RegisterSpellScript(era_ward_reflect);
    RegisterSpellScript(era_mag_cold_snap);
}
