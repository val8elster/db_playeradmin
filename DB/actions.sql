INSERT INTO players (name)
VALUES
    ('Player1'),
	('Player2'),
	('Player3'),
	('Player4'),
	('Player5'),
	('Player6'),
	('Player7'),
	('Player8'),
	('Player9'),
	('Player10'),
	('Player11'),
	('Player12'),
	('Player13'),
	('Player14'),
	('Player15'),
	('Player16'),
	('Player17'),
	('Player18'),
	('Player19'),
	('Player20'),
	('Player21'),
	('Player22'),
	('Player23'),
	('Player24'),
	('Player25'),
	('Player26:tbdeleted');
	


INSERT INTO statisticsPlayer (playerId)
VALUES
	(1),
	(2),
	(3),
	(4),
	(5),
	(6),
	(7),
	(8),
	(9),
	(10),
	(11),
	(12),
	(13), 
	(14), 
	(15),
	(16),
	(17),
	(18),
	(19),
	(20),
	(21),
	(22),
	(23),
	(24),
	(25),
	(26);




SELECT initialize();



INSERT INTO plays (playerId)
VALUES 
	(1), 
	(2), 
	(3),
	(16),
	(17),
	(18);



INSERT INTO teams (teamname, teamLeaderId, active, gameId)
VALUES
	('Team1', 1, B'1', 1),
	('Team2', 2, B'1', 1),
	('Team3', 3, B'1', 1),
	('Team4', 16, B'1', 2),
	('Team5', 17, B'1', 2),
	('Team6', 18, B'1', 2);



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 1, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 2, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 3, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 4, 2
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 5, 2
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 6, 2
FROM players
WHERE NOT EXISTS (
    SELECT playerId
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



SELECT check_complete_teams();



INSERT INTO questions(questionId, qname, answer1, answer2, answer3, answer4, rightanswer)
VALUES
    (1, 'welche farbe hat der Himmel?', 'blau', 'gelb', 'pink', 'grün',1),
    (2, 'was ist Schnee','wasser','blut','Himbeersaft','Cola',1),
    (3, 'welche farbe hat die Milch?', 'blau', 'gelb', 'pink', 'weiß', 4),
    (4, 'was ist ein Baum ', 'wasser', 'Pflanze', 'Himbeersaft', 'Cola', 2),
    (5, 'welche farbe hat der Mars?', 'schwarz', 'Schokolade', 'orange', 'grün', 3),
    (6, 'was ist eis','wasser', 'lecker', 'Himbeersaft', 'Cola', 2),
    (7, 'welche farbe hat das wasser?', 'blau', 'kalt', 'Loch Ness', 'grün', 3),
    (8, 'was ist eine Katze', 'wasser', 'Tier', 'Himbeersaft', 'Süß', 4),
	(9, 'ist der himmel blau?' , 'blubb', 'A', 'miau', 'ich bin farbenblind', 4);



INSERT INTO statisticsQuestions(questionId, difficulty)
VALUES
	(1, 1),
	(2, 1),
	(3, 1),
	(4, 1),
	(5, 1),
	(6, 1),
	(7, 1),
	(8, 1),
	(9, 1);



SELECT add_questions_to_session(1, 2, 3, 4, 7);