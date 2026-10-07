# Does sacking a Premier League manager work?

**Short answer:** teams do pick up after a mid-season manager change, but no more than similar teams who kept their manager.

**Dashboard:** https://public.tableau.com/app/profile/imran.ahmed5104/viz/PremierLeagueIstheNewManagerBounceReal/Doessackingamanagerwork

## Why I did this

I'm a Chelsea fan, and Chelsea changed manager mid-season six times in the 11 seasons I looked at. Every time it happens, the same line comes out: the "new manager bounce". I wanted to know if the bounce is real or just something we all repeat.

## What I expected vs. what the data showed

Going in, I expected what I'd read elsewhere: a short lift of about +0.3 to +0.5 points per game, fading within 10 to 15 games.

I took 57 mid-season manager changes from 2015/16 to 2025/26 and compared each club's 10 league games before the change with its 10 games after.

- Before the change, clubs averaged **0.78** points per game. After, **1.21**. That's a lift of +0.43, right inside what I predicted.
- The fade didn't show up in the 10 games I measured. Games 1 to 5 averaged 1.18 and games 6 to 10 averaged 1.24.
- 45 of the 57 clubs did better after the change than before it.

So far, that looks like the bounce is real. It isn't that simple.

## The check that changed the answer

Clubs sack managers at their lowest point. In my data, the last two games before a change averaged 0.39 and 0.25 points, while the eight games before those averaged about 0.89. A team on a run that bad usually improves whoever is in charge.

So the real question is not "did they improve?" but "did they improve more than a team in the same hole that kept its manager?"

I built a comparison group from every club that did not change manager in a season, and matched each of my 57 changes to clubs with exactly the same points from their last 10 games.

- Clubs that changed manager went on to average **1.21**.
- Matched clubs that kept their manager went on to average **1.21**.

The lift is real, but the change of manager doesn't explain it.

## What I got wrong

**My prediction.** I expected the bounce to fade. In the 10 games I measured, it didn't. I also expected sacked teams to recover more than teams who kept their manager. They recovered by about the same amount.

**My first benchmark.** When I ranked the 57 changes against that benchmark, big clubs dominated the top. That was just a flaw in my method, not a finding. A big-six club on a bad run was being compared with normal sides at their normal level, so of course it recovered further.

I rebuilt the benchmark to match on recent form **and** club tier (big six vs everyone else):

| | Actual after the change | Expected | Changes |
|---|---|---|---|
| Big six | 1.68 | 1.70 | 12 |
| Other clubs | 1.08 | 1.16 | 45 |

Against this fairer benchmark (1.27 on average), 26 changes did better and 31 did worse, with big swings both ways. On average the difference is -0.07 points per game, which with 57 changes this varied is not distinguishable from zero.

## Caveats

- **57 changes is a small sample.** "No effect on average" doesn't mean no individual change ever worked.
- **The big-six comparison is thin.** For the worst big-six slumps, the benchmark rests on only one or two other club-seasons.
- **Clubs choose when to sack.** Clubs that keep their manager may differ from clubs that don't in ways I can't see in results data.
- **The comparison windows overlap.** The 2,831 comparison rows come from 149 club-seasons, so they aren't independent.
- **League points only, 10 games each side.** Nothing here covers fixture difficulty or what happens the following season.
- **30 changes were left out** because they came too early or too late in a season to have 10 games either side.

## The data

- **Match results:** [football-data.co.uk](https://www.football-data.co.uk/englandm.php), 11 Premier League seasons, 4,180 matches.
- **Manager changes:** compiled by hand from the "Managerial changes" table on each season's Wikipedia page. 87 mid-season changes in total. I skipped pre-season and post-season changes and caretaker hand-overs. A match played on the day a manager left counts as his last game.

Cleaning notes: column counts differ between seasons, one season uses two-digit years, and my hand-typed team names needed trimming and matching to the results data. An anti-join check confirms all 87 changes match a club and season.

## Tools & how to reproduce

SQL in DuckDB (window functions, CTEs, an anti-join), Excel for compiling the manager changes, Tableau Public for the dashboard.

```bash
mkdir -p data/raw && cd data/raw
for s in 1516 1617 1718 1819 1920 2021 2122 2223 2324 2425 2526; do
  curl -L -A "Mozilla/5.0" -o "E0_$s.csv" "https://www.football-data.co.uk/mmz4281/$s/E0.csv"
done
cd ../..
duckdb pl.duckdb < queries.sql
```

`queries.sql` rebuilds every table and result from the raw files, in 13 commented steps.
