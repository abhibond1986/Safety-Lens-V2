// lib/services/kb_seed_data.dart
// SAIL Safety Lens V2 — Knowledge Base seed data
//
// Comprehensive safety legislation extracts for AI Scan & Near Miss:
//   • Factories Act 1948 — Chapter IV (Safety) sec 21–41
//   • Factories Act 1948 — Chapter IVA (Hazardous Processes) sec 41A–41H
//   • Chhattisgarh Factories Rules — key safety rules
//   • Odisha Factories Rules — key safety rules
//   • Tamil Nadu Factories Rules — key safety rules
//   • Bihar Factories Rules — key safety rules
//
// Loaded by LocalDB.seedKnowledgeBase() when the admin presses
// "Seed Default KB" in the Knowledge tab.

class KbSeedData {
  /// Each entry becomes one knowledge document in LocalDB.
  /// Keys: title, content, source.
  static const List<Map<String, String>> entries = [

    // ════════════════════════════════════════════════════════════
    // FACTORIES ACT 1948 — CHAPTER IV (SAFETY)
    // ════════════════════════════════════════════════════════════

    {
      'title': 'FA 1948 S21 — Fencing of machinery',
      'source': 'Factories Act 1948, Chapter IV, Section 21',
      'content': '''Every dangerous part of any machinery in a factory shall be securely fenced by safeguards of substantial construction which shall be constantly maintained and kept in position while the parts of machinery they are fencing are in motion or in use.

Mandatory items requiring fencing:
- Every moving part of a prime mover and every flywheel connected to a prime mover, whether the prime mover or flywheel is in the engine house or not
- The headrace and tailrace of every water-wheel and water turbine
- Any part of a stock-bar which projects beyond the head stock of a lathe
- Every part of an electric generator, a motor or rotary converter
- Every part of transmission machinery
- Every dangerous part of any other machinery

CORRECTIVE ACTION: Install fixed guards or interlocked guards as per IS 5905, IS 4682-3. For point-of-operation guards, follow IS 11572. All guards must be in place before machine is energised.

PENALTY: Sec 92 — up to 2 years imprisonment + Rs 1,00,000 fine.''',
    },

    {
      'title': 'FA 1948 S22 — Work on or near machinery in motion',
      'source': 'Factories Act 1948, Chapter IV, Section 22',
      'content': '''Where in any factory it becomes necessary to examine any part of machinery referred to in S21 while the machinery is in motion, or to carry out lubrication or other adjusting operation while the machinery is in motion, such examination or operation shall be made only by a specially trained adult male worker wearing tight-fitting clothing.

Conditions:
1. Worker must be specially trained.
2. Name must be recorded in the register of adult male workers prescribed.
3. Tight-fitting clothing supplied by the occupier.
4. No woman or young person shall be allowed to clean, lubricate or adjust any part of a prime mover or transmission machinery while it is in motion.
5. No worker shall enter any space between fixed structure and any part of transmission machinery if the space is less than 18 inches (45 cm).

CORRECTIVE ACTION: LOTO (Lock-Out-Tag-Out) per IS 14489. Use only trained personnel with documented authorization. Maintain register of trained male workers.''',
    },

    {
      'title': 'FA 1948 S23 — Employment of young persons on dangerous machines',
      'source': 'Factories Act 1948, Chapter IV, Section 23',
      'content': '''No young person (under 18 years) shall be required or allowed to work at any machine to which this section applies, unless:
(a) He has been fully instructed as to the dangers arising in connection with the machine and the precautions to be observed;
(b) He has received sufficient training in work at the machine; OR
(c) He is under adequate supervision by a person who has thorough knowledge and experience of the machine.

CORRECTIVE ACTION: Verify age of all operators. Maintain training records. Display warning notices in vernacular. SAIL plants typically exclude operators under 21 from any heavy machinery operation under their own SOPs.''',
    },

    {
      'title': 'FA 1948 S24 — Striking gear and devices for cutting off power',
      'source': 'Factories Act 1948, Chapter IV, Section 24',
      'content': '''In every factory:
(a) Suitable striking gear or other efficient mechanical appliance shall be provided and maintained and used to move driving belts to and from fast and loose pulleys which form part of the transmission machinery, and such gear or appliance shall be so constructed, placed and maintained as to prevent the belt from creeping back on to the fast pulley.
(b) Driving belts when not in use shall not be allowed to rest or ride upon shafting in motion.
(c) Suitable devices for cutting off power in emergencies from running machinery shall be provided and maintained in every workroom.

When a device which can inadvertently shift from "off" to "on" position is provided in a factory to cut off power, arrangements shall be provided for locking the device in safe position to prevent accidental starting of the transmission machinery or other machines to which the device is fitted.

CORRECTIVE ACTION: Emergency stop buttons (mushroom-head, red) within reach of every operator. Lockable disconnects on every machine. Quarterly testing of e-stops documented.''',
    },

    {
      'title': 'FA 1948 S25 — Self-acting machines',
      'source': 'Factories Act 1948, Chapter IV, Section 25',
      'content': '''No traversing part of a self-acting machine in any factory and no material carried thereon shall, if the space over which it runs is a space over which any person is liable to pass, whether in the course of his employment or otherwise, be allowed to run on its outward or inward traverse within a distance of 45 centimetres from any fixed structure which is not part of the machine.

CORRECTIVE ACTION: Maintain minimum 45 cm clearance. Install physical barriers, pull-cords, or photoelectric sensors. Mark traverse zones with floor-painted yellow lines.''',
    },

    {
      'title': 'FA 1948 S26 — Casing of new machinery',
      'source': 'Factories Act 1948, Chapter IV, Section 26',
      'content': '''In all machinery driven by power and installed in any factory after the commencement of this Act:
(a) Every set screw, bolt or key on any revolving shaft, spindle, wheel or pinion shall be so sunk, encased or otherwise effectively guarded as to prevent danger.
(b) All spur, worm and other toothed or friction gearing which does not require frequent adjustment while in motion shall be completely encased, unless it is so situated as to be as safe as it would be if it were completely encased.

CORRECTIVE ACTION: All new equipment to comply at procurement stage. Existing equipment to be retrofitted during major overhauls. Document type-tested certificates.''',
    },

    {
      'title': 'FA 1948 S28 — Hoists and lifts',
      'source': 'Factories Act 1948, Chapter IV, Section 28',
      'content': '''In every factory:
(a) Every hoist and lift shall be of good mechanical construction, sound material and adequate strength.
(b) Properly maintained, and thoroughly examined by a competent person at least once in every period of six months, and a register kept containing the prescribed particulars of every such examination.
(c) Enclosed by substantial gates of such a nature that, when the cage is not at the landing the gate shall remain closed.
(d) The maximum safe working load shall be plainly marked on every hoist or lift, and no load greater than such load shall be carried thereon.
(e) The cage shall be fitted with a gate which prevents any person or thing from falling out of the cage.
(f) Efficient devices shall be provided and maintained to support the cage in the event of breakage of the ropes, chains, etc.
(g) An efficient automatic device to prevent the cage from over-running.

CORRECTIVE ACTION: Six-monthly thorough examination by competent person (FORM No. 35 under Factories Rules). Display SWL prominently. Interlocked gates mandatory. Annual load test at 125% of SWL.''',
    },

    {
      'title': 'FA 1948 S29 — Lifting machines, chains, ropes and lifting tackles',
      'source': 'Factories Act 1948, Chapter IV, Section 29',
      'content': '''Every lifting machine and every chain, rope and lifting tackle for the purpose of raising or lowering persons, goods or materials shall be:
(a) Of good construction, sound material and adequate strength and free from defects.
(b) Properly maintained.
(c) Thoroughly examined by a competent person at least once in every period of twelve months, and a register of all such examinations kept.

Provided that:
(i) No lifting machine and no chain, rope or lifting tackle shall, except for the purpose of test, be loaded beyond the safe working load which shall be plainly marked thereon, together with an identification mark.
(ii) While any person is employed or working on or near the wheel track of a travelling crane, effective measures shall be taken to ensure that the crane does not approach within 6 metres of that place.

CORRECTIVE ACTION: Annual thorough examination (Form 11 register). Pre-use visual inspection per shift. Colour-coding system for inspection status. EOT crane operators to hold valid competency certificates.''',
    },

    {
      'title': 'FA 1948 S30 — Revolving machinery',
      'source': 'Factories Act 1948, Chapter IV, Section 30',
      'content': '''In every room in a factory in which the process of grinding is carried on, a notice indicating the maximum safe working peripheral speed of every grindstone or abrasive wheel, the speed of the shaft or spindle upon which the wheel is mounted, and the diameter of the pulley upon such shaft or spindle necessary to secure such safe working peripheral speed, shall be permanently affixed.

Speeds indicated in notices shall not be exceeded. Effective measures shall be taken to ensure that the safe working peripheral speed of every revolving vessel, cage, basket, flywheel, pulley, disc or similar appliance driven by power is not exceeded.

CORRECTIVE ACTION: Display speed-RPM chart at every grinding station. Use only marked wheels per IS 1591/IS 4581. Test mounting daily before use. Wheel selection per material per IS 5687.''',
    },

    {
      'title': 'FA 1948 S31 — Pressure plant',
      'source': 'Factories Act 1948, Chapter IV, Section 31',
      'content': '''If in any factory, any plant or machinery or any part thereof is operated at a pressure above atmospheric pressure, effective measures shall be taken to ensure that the safe working pressure of such plant or machinery or part is not exceeded.

CORRECTIVE ACTION: Hydrostatic test every 4 years; ultrasonic thickness gauging every 2 years per IBR. Maintain Form 8 (Boilers) / SMPV records for pressure vessels. Calibrated safety relief valves with annual recalibration. Pressure gauges shall be tested annually.

Related rules:
- SMPV (Static and Mobile Pressure Vessels) Rules 2016
- Indian Boiler Regulations 1950
- Gas Cylinders Rules 2016''',
    },

    {
      'title': 'FA 1948 S32 — Floors, stairs and means of access (Working at Height)',
      'source': 'Factories Act 1948, Chapter IV, Section 32',
      'content': '''In every factory:
(a) All floors, steps, stairs, passages and gangways shall be of sound construction and properly maintained and shall be kept free from obstructions and substances likely to cause persons to slip, and where it is necessary to ensure safety, steps, stairs, passages and gangways shall be provided with substantial handrails.
(b) There shall, so far as is reasonably practicable, be provided and maintained safe means of access to every place at which any person is at any time required to work.
(c) When any person has to work at a height from where he is liable to fall, provision shall be made, so far as is reasonably practicable, by fencing or otherwise, to ensure the safety of the person so working.

CRITICAL — WORKING AT HEIGHT (sub-section c):
This is the PRIMARY citation for any working-at-height hazard. NEVER cite S36 for height; S36 applies to confined space and dangerous fumes.

Mandatory controls per IS 3521:1999 Part 1, 2, 3:
- Edge protection or guardrails (top rail 950–1100 mm, mid-rail 470 mm, toe-board 150 mm) when working above 1.8 m / 6 feet
- Full body harness (IS 3521-1) anchored to a point capable of 22 kN
- Where guardrails not practicable: safety net (IS 11057) within 6 m below
- Issued under Work-at-Height Permit (PTW) signed by Safety Officer
- Toolbox talk before each shift
- No work in wind speed > 40 kmph or during rain/lightning''',
    },

    {
      'title': 'FA 1948 S33 — Pits, sumps, openings in floors etc.',
      'source': 'Factories Act 1948, Chapter IV, Section 33',
      'content': '''In every factory every fixed vessel, sump, tank, pit or opening in the ground or in a floor which, by reason of its depth, situation, construction or contents, is or may be a source of danger, shall be either securely covered or securely fenced.

The Inspector may direct that the means of egress or other safeguards as may be necessary shall be provided.

CORRECTIVE ACTION: Permanent fencing or grating around any opening > 30 cm wide. Where temporary opening required: barricade + flagman + warning signs. Edge protection ≥ 1 m height. Ladder/escape provision in confined sumps.''',
    },

    {
      'title': 'FA 1948 S34 — Excessive weights',
      'source': 'Factories Act 1948, Chapter IV, Section 34',
      'content': '''No person shall be employed in any factory to lift, carry or move any load so heavy as to be likely to cause him injury.

The State Government may make rules prescribing the maximum weights which may be lifted, carried or moved by adult men, adult women, adolescents and children.

Statutory limits (per Schedule under State Factories Rules — varies; common limits):
- Adult male: 55 kg max
- Adult female: 30 kg max
- Adolescent male (15–18 yrs): 30 kg
- Adolescent female (15–18 yrs): 20 kg
- Child labour: PROHIBITED under FA + Child Labour (Prohibition) Act

CORRECTIVE ACTION: Mechanical aids — trolleys, conveyors, hoists. Ergonomic risk assessment per IS 10804. Two-person lifts for 25–40 kg. Lifting & handling training annually. Display weight charts.''',
    },

    {
      'title': 'FA 1948 S35 — Protection of eyes',
      'source': 'Factories Act 1948, Chapter IV, Section 35',
      'content': '''In respect of any such manufacturing process carried on in any factory as may be prescribed, being a process which involves:
(a) Risk of injury to the eyes from particles or fragments thrown off in the course of the process, or
(b) Risk to the eyes by reason of exposure to excessive light,
the State Government may by rules require that effective screens or suitable goggles shall be provided for the protection of persons employed on, or in the immediate vicinity of, the process.

CORRECTIVE ACTION:
- Welding: IS 1179 grade welding goggles or full face shield (shade no. 10–14)
- Grinding: IS 5983 impact-resistant goggles
- Cutting/chipping: IS 5983 + face shield
- Laser: IS 14624 laser-specific protection (wavelength-rated)
- Chemical splash: IS 7524 chemical splash goggles
- High light intensity (furnace): IS 4770 IR-blocking goggles''',
    },

    {
      'title': 'FA 1948 S36 — Confined space / dangerous fumes, gases',
      'source': 'Factories Act 1948, Chapter IV, Section 36',
      'content': '''In any factory no person shall be required or allowed to enter any chamber, tank, vat, pit, pipe, flue or other confined space in which dangerous fumes are likely to be present to such an extent as to involve risk of persons being overcome thereby, unless it is provided with a manhole of adequate size or other effective means of egress.

No person shall be required or allowed to enter any confined space until all practicable measures have been taken:
(a) To remove any fumes or gas which may be present;
(b) To prevent the ingress of fumes or gas;
(c) Unless either:
    (i) A certificate in writing has been given by a competent person, based on a test carried out by him, that the space is reasonably free from dangerous fumes/gas and fit for entry, OR
    (ii) The worker is wearing suitable breathing apparatus and a belt securely attached to a rope, the free end of which is held by a person standing outside.

CRITICAL — CONFINED SPACE ENTRY (CSE):
This is the PRIMARY citation for any confined space hazard. NOT for working at height (that is S32c).

Mandatory controls per IS 14489:2018:
- Confined Space Entry Permit (PTW) signed by competent Safety Officer
- Gas test before entry: O2 (19.5–23.5%), LEL (<10%), H2S (<10 ppm), CO (<25 ppm)
- Continuous gas monitoring during work
- Standby man (attendant) at all times — must hold tripod + winch + rescue gear
- SCBA / SABA for IDLH or O2 deficient atmospheres
- Lighting: 24V or pneumatic only (S36A)
- Communication system between entrants and attendant
- Rescue plan documented and rehearsed
- Forbidden materials/sources of ignition listed on permit''',
    },

    {
      'title': 'FA 1948 S36A — Precautions regarding portable electric light',
      'source': 'Factories Act 1948, Chapter IV, Section 36A',
      'content': '''In any factory:
(a) No portable electric light or any other electric appliance of voltage exceeding 24 volts shall be permitted for use inside any chamber, tank, vat, pit, pipe, flue or other confined space unless adequate safety devices are provided.
(b) If any inflammable gas, fume or dust is likely to be present in such chamber, etc., no lamp or light other than that of flame-proof construction shall be permitted to be used therein.

CORRECTIVE ACTION:
- 24V SELV transformers for confined-space lighting (IS 9628)
- Flameproof Ex'd' luminaires (IS 2148 / IEC 60079-1) for hazardous areas
- Battery-operated intrinsically safe torches (Ex'ia' per IEC 60079-11) for entry inspection
- Test all portable lights for insulation resistance before each use''',
    },

    {
      'title': 'FA 1948 S37 — Explosive or inflammable dust, gas etc.',
      'source': 'Factories Act 1948, Chapter IV, Section 37',
      'content': '''Where in any factory any manufacturing process produces dust, gas, fume or vapour of such character and to such extent as to be likely to explode on ignition, all practicable measures shall be taken to prevent any such explosion by:
(a) Effective enclosure of the plant or machinery used in the process;
(b) Removal or prevention of the accumulation of such dust, gas, fume or vapour;
(c) Exclusion or effective enclosure of all possible sources of ignition.

Where in any factory the plant or machinery used in a process referred to in sub-section (1) is not so constructed as to withstand the probable pressure which such an explosion as aforesaid would produce, all practicable measures shall be taken to restrict the spread and effects of the explosion by the provision in the plant or machinery of chokes, baffles, vents or other effective appliances.

CORRECTIVE ACTION:
- Hazardous area classification per IS/IEC 60079-10
- Equipment selection per IEC 60079 series (Ex'd', Ex'e', Ex'ia' etc.)
- Dust collection per IS 11457; bonding & earthing per IS 3043
- Hot work permit (PTW) mandatory in classified zones
- Explosion vents per NFPA 68 / IS 15482''',
    },

    {
      'title': 'FA 1948 S38 — Precautions in case of fire',
      'source': 'Factories Act 1948, Chapter IV, Section 38',
      'content': '''In every factory, all practicable measures shall be taken to prevent outbreak of fire and its spread, both internally and externally, and to provide and maintain:
(a) Safe means of escape for all persons in the event of a fire;
(b) The necessary equipment and facilities for extinguishing fire.

Effective measures shall be taken to ensure that in every factory all the workers are familiar with the means of escape in case of fire and have been adequately trained in the routine to be followed in such case.

CORRECTIVE ACTION:
- NBC 2016 Part 4 compliant fire detection (smoke + heat) and alarm
- Fire extinguishers per IS 2190 — ABC/CO2/foam by class of risk; quarterly inspection
- Exit signs (photoluminescent, IS 15390), emergency lighting (IS 9583)
- Min 2 means of egress per floor; travel distance < 22.5 m
- Fire drill every 6 months, documented
- Fire NOC from State Fire Services renewed annually''',
    },

    {
      'title': 'FA 1948 S40A & S40B — Maintenance of buildings & Safety Officers',
      'source': 'Factories Act 1948, Chapter IV, Sections 40A and 40B',
      'content': '''S40A — Maintenance of buildings:
If it appears to the Inspector that any building or part of a building in a factory is in such a state of disrepair as is likely to lead to conditions detrimental to the health and welfare of the workers, he may serve on the occupier or manager an order in writing specifying the measures which in his opinion should be taken and requiring the same to be carried out before such date as is specified in the order.

S40B — Safety Officers:
In every factory:
(i) Wherein 1000 or more workers are ordinarily employed, OR
(ii) Wherein any manufacturing process or operation is carried on which involves any risk of bodily injury, poisoning or disease, or any other hazard to health, to the persons employed in the factory,
the occupier shall employ such number of Safety Officers as may be specified in that notification.

Duties, qualifications and conditions of service of Safety Officers shall be such as may be prescribed by the State Government.

CORRECTIVE ACTION — SAIL specific:
- Annual building safety audit per IS 14458-1
- Structural condition survey every 5 years
- Safety Officer cadre with B.E./B.Tech + Diploma in Industrial Safety (DIS) from RLI/CLI
- Safety Officer : Worker ratio per state rule (1:1000 typical)''',
    },

    // ════════════════════════════════════════════════════════════
    // FACTORIES ACT 1948 — CHAPTER IVA (HAZARDOUS PROCESSES)
    // ════════════════════════════════════════════════════════════

    {
      'title': 'FA 1948 S41A — Site Appraisal Committee for hazardous processes',
      'source': 'Factories Act 1948, Chapter IVA, Section 41A',
      'content': '''For the purposes of advising the State Government to consider applications for grant of permission for the initial location of a factory involving a hazardous process or for the expansion of any such factory, the State Government may appoint a Site Appraisal Committee.

The Committee shall consist of:
(a) The Chief Inspector — Chairman
(b) A representative of the Central Board for the Prevention and Control of Water Pollution
(c) A representative of the Central Board for the Prevention and Control of Air Pollution
(d) A representative of the State Board for the Prevention and Control of Water Pollution
(e) A representative of the State Board for the Prevention and Control of Air Pollution
(f) A representative of the Department of Environment in the State
(g) A representative of the Meteorological Department of the Government of India
(h) An expert in the field of occupational health
(i) A representative of the Town Planning Department of the State Government
(j) Up to 5 other co-opted members from local authority/scientific institutions.

The Committee shall examine the application for the establishment of a factory involving hazardous process and make its recommendation within 90 days. ''',
    },

    {
      'title': 'FA 1948 S41B — Compulsory disclosure of information',
      'source': 'Factories Act 1948, Chapter IVA, Section 41B',
      'content': '''The occupier of every factory involving a hazardous process shall:
(a) Disclose in the manner prescribed all information regarding dangers, including health hazards, and the measures to overcome such hazards arising from the exposure to or handling of the materials or substances in the manufacture, transportation, storage and other processes, to the workers employed in the factory, the Chief Inspector, the local authority within whose jurisdiction the factory is situated and the general public in the vicinity.

(b) At the time of registering the factory involving a hazardous process, lay down a detailed policy with respect to the health and safety of the workers and intimate such policy to the Chief Inspector and the local authority.

(c) Draw up an on-site emergency plan and detailed disaster control measures and make known to the workers employed and to the general public living in the vicinity of the factory the safety measures required to be taken in the event of an accident taking place.

CORRECTIVE ACTION — SAIL specific:
- MSDS available at every storage point in vernacular
- Annual SHE policy review signed by occupier
- Mock drills every 6 months with district authorities
- Public information meeting in adjacent panchayat annually''',
    },

    {
      'title': 'FA 1948 S41C — Specific responsibility of occupier in relation to hazardous processes',
      'source': 'Factories Act 1948, Chapter IVA, Section 41C',
      'content': '''Every occupier of a factory involving any hazardous process shall:
(a) Maintain accurate and up-to-date health records or, as the case may be, medical records of the workers in the factory who are exposed to any chemical, toxic or any other harmful substances which are manufactured, stored, handled or transported.
(b) Appoint persons who possess qualifications and experience in handling hazardous substances and are competent to supervise such handling within the factory.
(c) Provide for medical examination of every worker:
   (i) Before such worker is assigned to a job involving the handling of, or working with, a hazardous substance, and
   (ii) While continuing in such job, and after he has ceased to work in such job, at intervals not exceeding twelve months.

CORRECTIVE ACTION:
- Pre-employment + annual medical exam by Factory Medical Officer (FMO)
- Audiometry, lung function (spirometry), eye test, vision test, blood/urine where required
- Records retained min 30 years per state rule''',
    },

    {
      'title': 'FA 1948 S41G — Workers participation in safety management',
      'source': 'Factories Act 1948, Chapter IVA, Section 41G',
      'content': '''The occupier shall, in every factory where a hazardous process takes place, or where hazardous substances are used or handled, set up a Safety Committee consisting of equal number of representatives of workers and management to promote co-operation between the workers and the management in maintaining proper safety and health at work and to review periodically the measures taken in that behalf.

The Safety Committee shall meet at intervals as may be prescribed under the rules (typically once a quarter).

CORRECTIVE ACTION:
- Constitute Safety Committee with elected worker reps + management
- Minimum 4 meetings per year, minuted
- Worker reps trained in safety per Bipartite Committee guidelines
- Open agenda — workers can raise safety issues without retaliation''',
    },

    {
      'title': 'FA 1948 S41H — Right of workers to warn about imminent danger',
      'source': 'Factories Act 1948, Chapter IVA, Section 41H',
      'content': '''Where the workers employed in any factory engaged in a hazardous process have reasonable apprehension that there is a likelihood of imminent danger to their lives or health due to any accident, they may bring the same to the notice of the occupier, agent, manager or any other person who is in-charge of the factory or the process concerned directly or through their representatives in the Safety Committee and simultaneously bring the same to the notice of the Inspector.

It shall be the duty of such occupier, agent, manager or the person in-charge of the factory or process to take immediate remedial action if he is satisfied about the existence of such imminent danger and send a report forthwith of the action taken to the nearest Inspector.

If the occupier, agent, manager or the person in-charge referred to above is not satisfied about the existence of any imminent danger as apprehended by the workers, he shall, nevertheless, refer the matter forthwith to the nearest Inspector whose decision on the question of the existence of such imminent danger shall be final.

CORRECTIVE ACTION:
- "Right to Refuse Unsafe Work" policy displayed in vernacular
- Worker hotline to safety officer (no retribution clause)
- Imminent danger logbook reviewed weekly
- Inspector contact details posted at every entry gate''',
    },

    // ════════════════════════════════════════════════════════════
    // CHHATTISGARH FACTORIES RULES — KEY SAFETY RULES
    // ════════════════════════════════════════════════════════════

    {
      'title': 'Chhattisgarh Factories Rules — Safety Officer & Committee',
      'source': 'CG Factories Rules, Rules 73A–73D',
      'content': '''APPLIES TO BSP — Bhilai Steel Plant.

Rule 73A — Safety Officer mandatory in factories:
- Employing 500 or more workers, OR
- Carrying out any hazardous process listed in First Schedule of FA 1948.

Number of Safety Officers:
- 500–1000 workers: 1 Safety Officer
- 1001–2000 workers: 2 Safety Officers
- Each additional 2000: 1 additional Safety Officer

Qualifications:
- Degree in engineering recognised by AICTE + Post-Diploma in Industrial Safety from RLI/CLI/State approved institute, OR
- Equivalent qualification approved by Chief Inspector

Rule 73C — Safety Committee:
- Constituted in every factory employing 250 or more workers
- Members: equal management and worker reps, minimum 4 each, maximum 12 each
- Quarterly meeting mandatory; minutes copied to Chief Inspector

CORRECTIVE ACTION for BSP:
- Verify Safety Officer cadre matches worker count
- Quarterly committee meetings logged
- Annual safety policy review per S41B
- Site Emergency Plan filed with District Magistrate''',
    },

    {
      'title': 'Chhattisgarh Factories Rules — Working at height & scaffolding',
      'source': 'CG Factories Rules, Rule 64',
      'content': '''APPLIES TO BSP. Citation under FA 1948 S32(c).

Rule 64 — Safe means of access, work at heights, and scaffolding:

Where any person is required to work at a place from which he is liable to fall a distance of more than 1.8 metres (6 feet):
(a) Secure footing and handhold shall be provided.
(b) Where this is not reasonably practicable, safety belts, life lines or safety nets conforming to IS 3521 shall be provided.

Scaffolding requirements:
- Material: sound and free from defects (no painted scaffolding to hide flaws)
- Boards: minimum 38 mm thick × 200 mm wide, fully planked
- Toe-boards: minimum 150 mm high
- Guard rails: 1 m above platform, intermediate rail at 0.5 m
- Maximum span: 2.4 m for putlogs, 1.8 m for ledgers
- Inspected by competent person before use and weekly thereafter
- Tag system (green = safe, red = unsafe, yellow = under construction)

Mobile scaffold:
- Base width minimum 1/3 of height
- Wheels locked before use
- Workers shall descend before moving

Ladders:
- Conforming to IS 3696
- Inclined 1:4 (75 degrees)
- Extend 1 m above landing
- Secured at top (or held by another worker)''',
    },

    {
      'title': 'Chhattisgarh Factories Rules — Form numbers and registers',
      'source': 'CG Factories Rules, key forms list',
      'content': '''Key statutory forms for BSP under CG Factories Rules:

Form 1 — Application for registration of factory and grant of licence
Form 2 — Licence to work a factory
Form 3 — Notice of occupation
Form 7 — Health register (medical examination of young persons)
Form 11 — Register of compensable accidents
Form 12 — Register of leave with wages
Form 19 — Notice of accident under S88
Form 21 — Annual return (due by 31 January each year)
Form 22 — Half-yearly return (due by 31 July)
Form 35 — Register of examination of hoists, lifts (6-monthly per S28)
Form 36 — Register of examination of cranes, lifting machines (yearly per S29)
Form 37 — Register of examination of pressure plant (per S31)
Form 38 — Register of monitoring of working environment
Form 39 — Health register for hazardous process workers

CORRECTIVE ACTION: Maintain all forms current; Form 21 annual return is critical — late filing attracts penalty under S92. Forms 35–38 underpin S28, S29, S31 compliance.''',
    },

    {
      'title': 'Chhattisgarh Factories Rules — PPE & welfare amenities',
      'source': 'CG Factories Rules, Rules 81, 82 and Welfare Chapter',
      'content': '''APPLIES TO BSP.

Personal Protective Equipment (Rule 81 vicinity):
The occupier shall provide free of cost to workers exposed to any of the following:
- Eye injury risk: goggles to IS 1179 / IS 5983
- Head injury risk: safety helmets to IS 2925
- Foot injury risk: safety footwear to IS 15298 with steel toe + steel midsole for hot metal areas
- Hand injury risk: gloves to IS 4501 / IS 15869 by hazard type
- Respiratory hazard: respirators to IS 14746 / IS 13408 with appropriate filter class
- Hot metal splash: aluminised suit to IS 15748
- Welding: leather apron, gauntlets, welding shield IS 1179
- Acid/chemical: PVC/rubber suit to IS 4501
- Fall arrest: full body harness to IS 3521-1

Worker shall use, and the occupier shall enforce use of, all PPE provided. Failure attracts joint penalty under S92.

Welfare amenities (mandatory):
- Drinking water: cool potable water within 6 m of every workstation
- Washing facilities: 1 wash basin per 15 workers
- Latrines: 1 per 25 male workers, 1 per 15 female workers
- Canteen: mandatory if > 250 workers
- Creche: mandatory if > 30 women workers
- Rest room/lunch room: if > 150 workers''',
    },

    // ════════════════════════════════════════════════════════════
    // ODISHA FACTORIES RULES — KEY SAFETY RULES
    // ════════════════════════════════════════════════════════════

    {
      'title': 'Odisha Factories Rules — Safety Officer & Committee',
      'source': 'Odisha Factories Rules, Rules 73 series',
      'content': '''APPLIES TO RSP (Rourkela Steel Plant), OGOM (Odisha Group of Mines).

Safety Officer mandatory in factories:
- Employing 500 or more workers, OR
- Any hazardous process under First Schedule.

Number of Safety Officers:
- 500–999 workers: 1
- 1000–4999: 2
- 5000–9999: 3
- Each additional 5000: +1 (RSP being over 10,000 workers needs 4+)

Safety Committee — Odisha specific:
- Constituted within 90 days of factory commencement
- Min 4 management + 4 worker reps; max 12+12
- Worker reps elected by workers (NOT nominated by management)
- Tenure: 2 years
- Quorum: 50% of total + 1
- Meetings: minimum once per quarter; emergency meetings allowed
- Functions: Hazard identification, accident investigation, safety promotion, review of safety records

CORRECTIVE ACTION for RSP:
- Verify safety officer cadre per worker count
- Display safety committee members list at factory gate
- Send minutes to Chief Inspector Odisha within 15 days of meeting''',
    },

    {
      'title': 'Odisha Factories Rules — Hot work permit & confined space',
      'source': 'Odisha Factories Rules, hot work and CSE provisions',
      'content': '''APPLIES TO RSP.

Hot work permit (citation FA 1948 S37):
A written permit shall be issued before commencement of any hot work (welding, cutting, grinding producing sparks) in:
- Areas where flammable materials are stored/handled
- Confined spaces
- Areas designated as hazardous under hazardous area classification

Permit shall specify:
- Exact location and nature of work
- Date and time period (max 8 hours)
- Fire watch arrangement (must continue 30 minutes after work ends)
- Fire extinguisher staging
- Gas test results (LEL < 10%)
- Authorising Safety Officer's signature
- Worker name and ID

Confined Space Entry (citation FA 1948 S36):
- Written permit before each entry
- Gas test before entry: O2 (19.5–23.5%), LEL (<10%), H2S (<10 ppm), CO (<25 ppm)
- Continuous gas monitoring during work
- Standby man with rescue tripod, winch, SCBA
- Entry log: time in, time out, gas readings every 30 min
- Communication system entrant ↔ attendant
- 24V lighting (S36A)
- Flameproof lighting if flammable atmosphere

Permits maintained in Form 11A (Odisha specific) for 5 years.''',
    },

    {
      'title': 'Odisha Factories Rules — Notice of accidents & dangerous occurrences',
      'source': 'Odisha Factories Rules, accident reporting',
      'content': '''APPLIES TO RSP.

Reporting of accidents (FA 1948 S88 + Odisha Rules):

FATAL ACCIDENT or accident causing absence from work > 48 hours:
- Telephonic intimation to Inspector & District Magistrate within 4 hours
- Form 19 (written) within 24 hours
- Police report (if fatal) within 24 hours

NON-FATAL — > 48 hours absence:
- Form 19 within 24 hours

DANGEROUS OCCURRENCE (defined in Rules):
- Bursting of pressure vessel, boiler explosion
- Collapse of crane, lifting machine
- Failure of lifting tackle resulting in fall of load > 50 kg
- Fire/explosion causing damage to building
- Spillage of toxic substances > 100 kg
- Electrical short circuit causing power outage > 1 hour or fire
- Collapse of building or scaffold
- Report on Form 19A within 24 hours (even if no injury)

ANNUAL RETURN of accidents:
- Form 21 by 31 January
- Statistics: fatal, non-fatal, severity, frequency rates

CORRECTIVE ACTION:
- Pre-printed Form 19 stack at safety office
- Inspector phone numbers displayed prominently
- Investigation per WSA 13 causes within 7 days
- Closure report within 30 days''',
    },

    {
      'title': 'Odisha Factories Rules — Mining areas (OGOM)',
      'source': 'Mines Act 1952 + Odisha Factories Rules overlap',
      'content': '''APPLIES TO OGOM — Odisha Group of Mines.

Mining areas under SAIL come under Mines Act 1952 + Mines Rules 1955 + relevant state-specific rules. The Factories Act applies to mineral processing and crushing units within mine premises.

Key safety requirements at mine areas:
- Statutory examination of haul roads, slopes, drainage by Mines Manager (Form B)
- DGMS (Directorate General of Mines Safety) approval for hazardous operations
- Blasting per Mines Rules 1955 Sec 158–168 + Indian Explosives Rules 2008
- Safety helmet, footwear, dust mask mandatory below ground or at face
- Self-contained self-rescuer (SCSR) for underground workers
- Stone dust barriers in coal mines
- Methane monitoring continuous
- Worker training under Mines Vocational Training Rules
- Statutory weekly safety meeting per Mines Rule 50

Concurrent compliance with State Factories Rules for surface/processing units:
- Crusher house: noise abatement per Noise Pollution Rules 2000
- Loading: lifting machinery per FA S29
- Diesel emissions: monitoring per Air (Prevention) Act 1981

CORRECTIVE ACTION:
- Maintain dual compliance file (Mines + Factories)
- Periodic DGMS audit ready file
- Form B (Mines) and Form 21 (Factories) annual returns
- Mine plan + section as per DGMS approved scale''',
    },

    // ════════════════════════════════════════════════════════════
    // TAMIL NADU FACTORIES RULES — KEY SAFETY RULES
    // ════════════════════════════════════════════════════════════

    {
      'title': 'Tamil Nadu Factories Rules — Safety provisions',
      'source': 'Tamil Nadu Factories Rules, key safety rules',
      'content': '''APPLIES TO SSP — Salem Steel Plant.

Tamil Nadu Factories Rules 1950 (as amended).

Safety Officer mandatory:
- Factory employing 500 or more workers
- Any hazardous process from First Schedule
- Numbers: 1 per 500 workers, scaled per worker count

Safety Committee:
- Constituted in factory > 250 workers OR hazardous process
- Equal worker + management reps
- Tenure 2 years
- Quarterly meetings minimum

PPE Schedule (TN specific list):
Specifies PPE for 47 categories of operation including:
- Stainless steel cold rolling (relevant to SSP): goggles + leather apron + safety shoes + heat-resistant gloves
- Annealing: aluminised face shield + heat-resistant suit + IS 3738 boots
- Pickling line: PVC suit + acid resistant gloves + face shield + respirator + safety shoes
- Slitter line: cut-resistant gloves (IS 15869 cut level 5) + safety shoes

Welfare amenities — TN specific:
- Drinking water cooler at every floor in summer (April–July)
- Wash basins with hot water if process involves oil/grease
- Crèche for any female workers (not just > 30)
- Canteen subsidy per TN Labour Welfare Fund

Reporting:
- Form 19 (TN) — accident report within 24 hours
- Form 21 annual return by 31 January
- Triennial safety audit by TN State Safety Officer panel

CORRECTIVE ACTION:
- Display TN Form 19 numbers next to safety office phone
- File annual safety audit by 31 March each 3rd year
- Subsidised canteen records audited annually''',
    },

    {
      'title': 'Tamil Nadu Factories Rules — Hazardous chemicals',
      'source': 'TN Factories Rules + MSIHC Rules 1989',
      'content': '''APPLIES TO SSP for pickling line acid handling and stainless steel processing.

Manufacture, Storage and Import of Hazardous Chemicals (MSIHC) Rules 1989 apply alongside FA 1948 Chapter IVA. Maximum Threshold Quantities trigger MSIHC compliance:
- HCl: 25 tonnes (MSIHC Schedule 3)
- HNO3: 50 tonnes
- H2SO4: 50 tonnes
- NaOH: 100 tonnes

Requirements above threshold:
1. Notification to Chief Inspector + State Pollution Control Board
2. Safety Report submission every 5 years
3. On-site emergency plan (rehearsed every 6 months)
4. Off-site emergency plan in coordination with district authorities
5. Worker training on chemical hazards
6. Medical surveillance per S41C
7. Public information disclosure annually
8. Display of Material Safety Data Sheet (MSDS) at every storage point

For SSP pickling line specifically:
- Acid storage in HDPE tank with secondary containment (110% of largest tank)
- Spill kit at every transfer point
- Eye wash + safety shower within 10 seconds of any acid contact point
- Continuous vapour extraction over pickling tank
- pH monitoring of effluent stream

CORRECTIVE ACTION:
- MSDS in Tamil + English at every chemical store
- Quarterly MSIHC inspection by Safety Officer
- Annual return to TNPCB''',
    },

    // ════════════════════════════════════════════════════════════
    // BIHAR FACTORIES RULES — KEY SAFETY RULES
    // ════════════════════════════════════════════════════════════

    {
      'title': 'Bihar Factories Rules — Safety provisions',
      'source': 'Bihar Factories Rules, key safety rules',
      'content': '''APPLIES TO units within Bihar.

Bihar Factories Rules 1950 (Bihar reorganisation 2000 retained applicability; Jharkhand has separate rules from 2002 onward — SAIL Ranchi HQ falls under Jharkhand Factories Rules).

Safety Officer mandatory:
- Factory employing 1000 or more workers
- Any hazardous process from First Schedule
- 1:1000 ratio (1 Safety Officer per 1000 workers; minimum 1)

Safety Committee composition:
- Equal management and worker representatives
- Members 4 to 12 each side
- Chairperson: occupier or his nominee (rotating with worker side optional)
- Quarterly meeting, minutes shared with Chief Inspector

Worker training:
- Induction training for new joiners (minimum 8 hours)
- Periodic refresher every 2 years
- Job-specific safety training before assignment to hazardous process

Welfare amenities:
- Drinking water within 6 m of every worker
- Latrines: 1 per 25 male, 1 per 15 female
- Canteen if > 250 workers
- Rest room if > 150 workers
- Crèche if > 30 women workers
- First aid: 1 box per 150 workers (Form 31 Bihar)

Reporting:
- Form 19 (Bihar) — accident within 24 hours
- Form 21 annual return by 31 January
- Form 23 — Notice of poisoning, disease (Schedule III)

CORRECTIVE ACTION:
- File annual return on time
- Maintain Form 19/19A/23 stationery at safety office
- Crèche and canteen comply with Bihar Labour Welfare Board norms''',
    },

    {
      'title': 'Bihar Factories Rules — Lifting machines & cranes',
      'source': 'Bihar Factories Rules supplementing FA S29',
      'content': '''APPLIES TO units in Bihar; analogous rules in Jharkhand for SAIL Ranchi HQ.

Examination and testing of lifting machines (Bihar specific schedule):

EOT Cranes:
- Initial proof test at 125% SWL by competent person before commissioning
- Annual thorough examination by competent person
- Quarterly inspection by factory's own engineer + record in Form 36
- Monthly preventive maintenance
- Pre-shift visual check by operator

Mobile cranes:
- Pre-shift test of load indicator and limit switches
- Outrigger inspection before each lift
- Ground bearing pressure assessment for picks > 80% SWL

Chain slings, wire rope slings, web slings:
- Colour coding by inspection quarter (Q1 red, Q2 yellow, Q3 green, Q4 blue)
- Withdraw from service if: kinks, broken wires > 10%, abrasion > 5%, corrosion
- Annual proof test 200% SWL for chain; 200% SWL for wire rope
- Maintain register Form 36

Forklifts:
- Operator licence (industrial truck competency)
- Pre-shift check (brakes, horn, lights, mast, forks)
- Load capacity chart displayed
- Annual inspection by competent person

CORRECTIVE ACTION:
- Display SWL prominently on every machine
- Colour-coded inspection tags visible on every sling
- Operator licences renewed every 2 years
- Form 36 register reviewed monthly''',
    },

    // ════════════════════════════════════════════════════════════
    // CROSS-REFERENCE QUICK MAPS (for AI prompt)
    // ════════════════════════════════════════════════════════════

    {
      'title': 'Hazard → Regulation Quick Reference',
      'source': 'SAIL Safety Lens — AI prompt aid',
      'content': '''CRITICAL CITATION RULES:

WORKING AT HEIGHT (any fall risk above 1.8 m / 6 ft):
→ ALWAYS cite FA 1948 S32(c) + IS 3521:1999 Part 1/2/3
→ NEVER cite S36 (S36 is for confined space/dangerous fumes ONLY)
→ Add state-specific: CG Rule 64 / Odisha equivalent / TN equivalent

CONFINED SPACE / DANGEROUS FUMES:
→ FA 1948 S36 + IS 14489:2018
→ FA S36A for portable lighting (24V/flameproof)

ELECTRICAL HAZARDS:
→ Indian Electricity Rules 1956 + CEA Regulations 2023
→ IS 5216 (workmen safety)
→ IS 3043 (earthing)

FIRE / EXPLOSION RISK:
→ FA 1948 S37 + S38
→ NBC 2016 Part 4
→ IS 2190 (fire extinguishers)
→ IS/IEC 60079 series for hazardous areas

LIFTING MACHINES, CRANES:
→ FA 1948 S29 + Form 36 register
→ IS 807 (cranes design)
→ IS 13367 (safety in use)

PRESSURE VESSELS:
→ FA 1948 S31
→ Indian Boiler Regulations 1950
→ SMPV (Static & Mobile Pressure Vessels) Rules 2016
→ Gas Cylinders Rules 2016

CHEMICALS / HAZARDOUS SUBSTANCES:
→ FA 1948 Chapter IVA (S41A–H)
→ MSIHC Rules 1989
→ Hazardous Wastes Rules 2016

PPE NON-COMPLIANCE:
→ FA 1948 S35 (eye) + State Rule (PPE schedule)
→ IS 2925 (helmet), IS 15298 (footwear), IS 4501/15869 (gloves)
→ IS 14746 (respirator)

LOTO / WORK ON LIVE MACHINERY:
→ FA 1948 S22 (machinery in motion)
→ IS 14489 (LOTO procedures)

NOISE:
→ Noise Pollution (Regulation & Control) Rules 2000
→ IS 9876 (occupational exposure limit: 90 dBA TWA 8hr)
→ FA S87 (notice of poisoning) for occupational disease

CHILD LABOUR / YOUNG PERSONS:
→ FA 1948 S23, S67, S68
→ Child & Adolescent Labour (Prohibition & Regulation) Act 1986

PROHIBITION OF EMPLOYMENT IN CERTAIN PROCESSES:
→ FA 1948 S27 (cotton openers — women + children)
→ FA 1948 Schedule (lead, manganese, asbestos exposure controls)

WSA 13 CAUSES (mandatory tagging per SAIL):
1. Failure of work conditions/procedures
2. Inadequate safety guarding
3. Inadequate PPE
4. Inadequate worker training
5. Inadequate supervision
6. Worker behavioural deviation
7. Mechanical/equipment failure
8. Electrical fault
9. Environmental (lighting, ventilation, temperature)
10. Housekeeping
11. Material handling
12. Permit-to-work failure
13. Emergency response inadequate''',
    },

    {
      'title': 'SAIL Plant List & Applicable State Rules',
      'source': 'SAIL Safety Lens — jurisdictional reference',
      'content': '''Each SAIL unit follows the State Factories Rules of its location, alongside the central Factories Act 1948.

SAIL Plant → State → Applicable State Rules:

BSP (Bhilai Steel Plant)         → Chhattisgarh → CG Factories Rules
DSP (Durgapur Steel Plant)       → West Bengal   → WB Factories Rules
RSP (Rourkela Steel Plant)       → Odisha        → Odisha Factories Rules
BSL (Bokaro Steel Plant)         → Jharkhand     → Jharkhand Factories Rules
ISP (IISCO Steel Plant, Burnpur) → West Bengal   → WB Factories Rules
ASP (Alloy Steels Plant)         → West Bengal   → WB Factories Rules
SSP (Salem Steel Plant)          → Tamil Nadu    → TN Factories Rules
CFP (Chandrapur Ferro Alloy)     → Maharashtra   → MH Factories Rules
CMO (Central Marketing Org)      → Various (Delhi HQ)
JGOM (Jharkhand Group of Mines)  → Jharkhand     → Mines Act + Jharkhand Rules
OGOM (Odisha Group of Mines)     → Odisha        → Mines Act + Odisha Rules
BSP(M) — BSP Mines               → Chhattisgarh  → Mines Act + CG Rules
Collieries — SAIL Collieries     → Jharkhand/WB  → Mines Act + state rules
SRU Kulti (Steel Refractory)     → West Bengal   → WB Factories Rules
SAIL HQ                          → Delhi/Ranchi  → Delhi/Jharkhand rules

AI Citation rule:
When generating findings for a SAIL plant, cite:
1. Central Factories Act 1948 section (always applies)
2. Applicable state rule for that plant's state
3. Relevant Indian Standard (IS) code
4. SAIL Safety Organisation Safety Guideline (SG/01–SG/41) where mapped''',
    },

  ];

  /// Total entries — for the seed UI to display count.
  static int get count => entries.length;
}
