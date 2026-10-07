-- Premier League: is the "new manager bounce" real?
-- Run from the premier-league folder:  duckdb pl.duckdb < queries.sql
-- Data: football-data.co.uk match results (2015/16 to 2025/26) + manager changes compiled by hand from Wikipedia.

-- 1. Load 11 seasons of match results
--    (column counts differ by season, 2016/17 uses 2-digit years, season lives in the filename)
CREATE OR REPLACE TABLE matches AS
SELECT
  regexp_extract(filename, 'E0_(\d{4})', 1) AS season,
  strptime(Date, ['%d/%m/%y', '%d/%m/%Y'])::DATE AS match_date,
  HomeTeam AS home_team,
  AwayTeam AS away_team,
  FTHG AS home_goals,
  FTAG AS away_goals,
  FTR AS result
FROM read_csv('data/raw/E0_*.csv',
              union_by_name = true,
              filename = true,
              types = {'Date': 'VARCHAR'});

-- 2. One row per team per match (8,360 rows, 11,550 points)
CREATE OR REPLACE TABLE team_matches AS
-- Home Team Perspective
SELECT
    season,
    match_date,
    home_team AS team,
    away_team AS opponent,
    'H' AS venue,
    home_goals AS goals_for,
    away_goals AS goals_against,
    CASE
        WHEN result = 'H' THEN 3
        WHEN result = 'D' THEN 1
        ELSE 0
    END AS points
FROM matches

UNION ALL

-- Away Team Perspective
SELECT
    season,
    match_date,
    away_team AS team,
    home_team AS opponent,
    'A' AS venue,
    away_goals AS goals_for,
    home_goals AS goals_against,
    CASE
        WHEN result = 'A' THEN 3
        WHEN result = 'D' THEN 1
        ELSE 0
    END AS points
FROM matches;

-- 3. Number each team's games within a season (1 to 38)
CREATE OR REPLACE TABLE team_matches AS
SELECT *,
    ROW_NUMBER() OVER (
        PARTITION BY season, team
        ORDER BY match_date ASC
    ) AS game_no
FROM team_matches;

-- 4. Load the hand-built manager changes (87 rows); TRIM guards against stray spaces
CREATE OR REPLACE TABLE manager_changes AS
SELECT
    season::VARCHAR AS season,
    TRIM(team) AS team,
    date_left::DATE AS date_left,
    outgoing,
    reason,
    incoming
FROM read_csv('data/manager_changes.csv');

-- 4b. Anti-join check: every change must match a team-season in the results (expect 0 rows)
SELECT mc.season, mc.team
FROM manager_changes mc
LEFT JOIN team_matches tm
  ON tm.season = mc.season AND tm.team = mc.team
WHERE tm.team IS NULL;

-- 5. Pin each change to the outgoing manager's last game;
--    keep only changes with 10 games before and 10 after in the same season (57 of 87)
CREATE OR REPLACE TABLE events AS
SELECT
    mc.season,
    mc.team,
    mc.outgoing,
    mc.reason,
    mc.date_left,
    MAX(tm.game_no) AS last_game
FROM manager_changes mc
INNER JOIN team_matches tm
    ON mc.season = tm.season
   AND mc.team = tm.team
   AND tm.match_date <= mc.date_left
GROUP BY
    mc.season,
    mc.team,
    mc.outgoing,
    mc.reason,
    mc.date_left
HAVING MAX(tm.game_no) BETWEEN 10 AND 28;

-- 6. Points per game before and after each change
CREATE OR REPLACE TABLE bounce AS
SELECT
    e.season,
    e.team,
    e.outgoing,
    e.reason,
    e.last_game,
    AVG(tm.points) FILTER (WHERE tm.game_no <= e.last_game) AS ppg_before,
    AVG(tm.points) FILTER (WHERE tm.game_no > e.last_game) AS ppg_after,
    AVG(tm.points) FILTER (WHERE tm.game_no BETWEEN e.last_game + 1 AND e.last_game + 5) AS ppg_after_1_5,
    AVG(tm.points) FILTER (WHERE tm.game_no BETWEEN e.last_game + 6 AND e.last_game + 10) AS ppg_after_6_10
FROM events e
INNER JOIN team_matches tm
    ON e.season = tm.season
   AND e.team = tm.team
   AND tm.game_no BETWEEN e.last_game - 9 AND e.last_game + 10
GROUP BY
    e.season,
    e.team,
    e.outgoing,
    e.reason,
    e.last_game;

-- 6b. The naive result: before vs after
SELECT
  ROUND(AVG(ppg_before), 2)     AS before,
  ROUND(AVG(ppg_after), 2)      AS after,
  ROUND(AVG(ppg_after_1_5), 2)  AS games_1_5,
  ROUND(AVG(ppg_after_6_10), 2) AS games_6_10
FROM bounce;

-- 7. Rolling form for every team at every point in the season
--    (pts_next_10 is only a full 10 games for game_no 10 to 28)
CREATE OR REPLACE TABLE rolling AS
SELECT
    season,
    team,
    game_no,
    SUM(points) OVER (
        PARTITION BY season, team
        ORDER BY game_no
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) AS pts_last_10,
    SUM(points) OVER (
        PARTITION BY season, team
        ORDER BY game_no
        ROWS BETWEEN 1 FOLLOWING AND 10 FOLLOWING
    ) AS pts_next_10
FROM team_matches;

-- 8. Control group: teams that did not change manager that season (2,831 rows)
CREATE OR REPLACE TABLE control AS
SELECT r.season, r.team, r.game_no, r.pts_last_10, r.pts_next_10
FROM rolling r
LEFT JOIN manager_changes mc
  ON r.season = mc.season
 AND r.team = mc.team
WHERE r.game_no BETWEEN 10 AND 28
  AND mc.team IS NULL;

-- 8b. Bad runs only (10 points or fewer from the last 10 games)
SELECT 'sacked' AS grp, COUNT(*) AS n,
       ROUND(AVG(ppg_before), 2) AS before,
       ROUND(AVG(ppg_after), 2)  AS after
FROM bounce
WHERE ROUND(ppg_before * 10) <= 10

UNION ALL

SELECT 'kept manager', COUNT(*),
       ROUND(AVG(pts_last_10) / 10.0, 2),
       ROUND(AVG(pts_next_10) / 10.0, 2)
FROM control
WHERE pts_last_10 <= 10;

-- 9. The fair comparison: each change matched to kept-manager teams
--    with exactly the same points from their last 10 games
WITH expected AS (
    SELECT
        pts_last_10,
        AVG(pts_next_10) / 10.0 AS expected_ppg
    FROM control
    GROUP BY pts_last_10
)
SELECT
    COUNT(*) AS n,
    ROUND(AVG(b.ppg_after), 2) AS actual_ppg,
    ROUND(AVG(e.expected_ppg), 2) AS expected_ppg
FROM bounce b
INNER JOIN expected e
   ON ROUND(b.ppg_before * 10) = e.pts_last_10;

-- 10. Average points by game relative to the change

CREATE OR REPLACE TABLE form_curve AS
     SELECT 
         CASE 
             WHEN tm.game_no <= e.last_game THEN tm.game_no - e.last_game - 1
             ELSE tm.game_no - e.last_game
         END AS rel_game,
         COUNT(*) AS n,
         ROUND(AVG(tm.points), 2) AS avg_points
     FROM events e
     INNER JOIN team_matches tm 
         ON e.season = tm.season 
        AND e.team = tm.team
        AND tm.game_no BETWEEN e.last_game - 9 AND e.last_game + 10
     GROUP BY rel_game
     ORDER BY rel_game;

-- 11. Each change with its tier-aware benchmark:
--     expected PPG from kept-manager teams matched on both club tier and recent form

CREATE OR REPLACE TABLE bounce_detail AS
WITH expected AS (
    SELECT 
        CASE 
            WHEN team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
            ELSE 'other'
        END AS tier,
        pts_last_10,
        AVG(pts_next_10) / 10.0 AS expected_ppg
    FROM control
    GROUP BY tier, pts_last_10
)
SELECT 
    b.season, 
    b.team, 
    CASE 
        WHEN b.team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
        ELSE 'other'
    END AS tier,
    b.outgoing, 
    b.reason, 
    b.last_game, 
    b.ppg_before, 
    b.ppg_after, 
    b.ppg_after_1_5, 
    b.ppg_after_6_10,
    ROUND(e.expected_ppg, 4) AS expected_ppg,
    ROUND(b.ppg_after - e.expected_ppg, 4) AS diff
FROM bounce b
INNER JOIN expected e
   ON CASE 
        WHEN b.team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
        ELSE 'other'
      END = e.tier
  AND ROUND(b.ppg_before * 10) = e.pts_last_10;


-- 12. Fairer benchmark: match each change on recent form AND club tier (big six vs other)
WITH expected AS (
    SELECT 
        CASE 
            WHEN team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
            ELSE 'other'
        END AS control_tier,
        pts_last_10,
        COUNT(*) AS n_control,
        AVG(pts_next_10) / 10.0 AS expected_ppg
    FROM control
    GROUP BY control_tier, pts_last_10
)
SELECT 
    CASE 
        WHEN b.team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
        ELSE 'other'
    END AS squad_tier,
    COUNT(*) AS total_sacked,
    COUNT(e.expected_ppg) AS matched_sacked,
    ROUND(AVG(b.ppg_after), 2) AS actual_ppg,
    ROUND(AVG(e.expected_ppg), 2) AS expected_ppg,
    ROUND(AVG(b.ppg_after - e.expected_ppg), 2) AS avg_diff
FROM bounce b
LEFT JOIN expected e
   ON CASE 
        WHEN b.team IN ('Man United', 'Chelsea', 'Arsenal', 'Man City', 'Liverpool', 'Tottenham') THEN 'big_six'
        ELSE 'other'
      END = e.control_tier
  AND ROUND(b.ppg_before * 10) = e.pts_last_10
GROUP BY squad_tier;

-- 13. Export the tables Tableau reads
COPY form_curve    TO 'output/form_curve.csv'    (HEADER);
COPY bounce_detail TO 'output/bounce_detail.csv' (HEADER);