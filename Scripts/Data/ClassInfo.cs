namespace Realmshatter;

/// <summary>Display names, rule-of-thumb descriptions and base stat lines of the unit classes.</summary>
public static class ClassInfo
{
	/// <summary>Display name of a class ("" for None).</summary>
	public static string GetName(UnitClass unitClass) => unitClass == UnitClass.None ? "" : unitClass.ToString();

	/// <summary>Short description of what the class is good at.</summary>
	public static string GetDescription(UnitClass unitClass) => unitClass switch
	{
		UnitClass.Swordsman => "Sturdy melee fighter with a solid hit.",
		UnitClass.Archer => "Fragile, but shoots from 3 tiles away.",
		UnitClass.Guardian => "Slow defender with a shield that soaks damage first.",
		UnitClass.Scout => "Very fast runner that grabs the zone early.",
		UnitClass.Lancer => "Mobile spearman with a hard thrust.",
		UnitClass.Mage => "Slow caster that strikes from 2 tiles away.",
		UnitClass.Cleric => "Mobile support that reaches 2 tiles.",
		UnitClass.Brute => "Heavy, slow bruiser with lots of HP.",
		UnitClass.Totem => "Immobile relay that never leaves its tile.",
		UnitClass.Worker => "Barely fights, but brings extra AP every turn.",
		_ => "",
	};

	/// <summary>Display name of a card's class, falling back to its role for class-less units.</summary>
	public static string ClassOrRole(CardData card) =>
		card.Class != UnitClass.None ? GetName(card.Class) : card.Role.ToString();

	/// <summary>"Archer · Burning, Arc" style line: class plus effects (keywords).</summary>
	public static string ClassWithEffects(CardData card)
	{
		string effects = KeywordInfo.Format(card.Keywords);
		string cls = ClassOrRole(card);
		return effects.Length > 0 ? $"{cls} · {effects}" : cls;
	}
}
