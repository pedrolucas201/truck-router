package handlers

import "testing"

// A regra que o Pedro escolheu em 17/09/2026, caso por caso. Se algum destes
// quebrar, a maioria para de valer ou passa a valer quando não devia — e o
// efeito é o motorista vendo um limite que ninguém votou.
func TestDecidirVotos(t *testing.T) {
	casos := []struct {
		nome string
		vs   []voto
		quer placar
	}{
		{"sem voto: ninguem manda",
			nil,
			placar{N: 0}},

		// O caso que o Pedro descreveu: Beto 80 x Fernando 90, so os dois.
		{"1x1 abaixo do piso: cada um segue com o seu",
			[]voto{{true, 80}, {true, 90}},
			placar{N: 2, Exists: true, Kmh: 0, MandaExists: false, MandaKmh: false}},

		{"1 voto so: nao manda em ninguem",
			[]voto{{true, 80}},
			placar{N: 1, Exists: true, MandaExists: false, MandaKmh: false}},

		// "se 90 pessoas concordam e 1 discorda, a que discorda aceita a da maioria"
		{"2x1 no piso: maioria manda pra todos",
			[]voto{{true, 80}, {true, 80}, {true, 90}},
			placar{N: 3, Exists: true, Kmh: 80, MandaExists: true, MandaKmh: true}},

		{"empate 2x2 com piso atingido: limite nao muda",
			[]voto{{true, 80}, {true, 80}, {true, 90}, {true, 90}},
			placar{N: 4, Exists: true, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"maioria diz que NAO existe",
			[]voto{{false, 0}, {false, 0}, {true, 80}},
			placar{N: 3, Exists: false, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"empate sobre existir: nao manda",
			[]voto{{false, 0}, {true, 80}, {false, 0}, {true, 80}},
			placar{N: 4, Exists: true, Kmh: 0, MandaExists: false, MandaKmh: false}},

		// Quem diz "nao existe" nao tem opiniao sobre a placa: se contasse como
		// voto de limite, um "nao existe" derrubaria o limite da maioria.
		{"quem vota nao-existe nao conta no limite",
			[]voto{{true, 80}, {true, 80}, {true, 80}, {false, 0}},
			placar{N: 4, Exists: true, Kmh: 80, MandaExists: true, MandaKmh: true}},

		// Dois votos de 80 nao atingem o piso de 3 COM numero, entao o limite
		// nao muda pra ninguem: publica 0 (= "nao mexe"), nao o mais votado.
		{"tres que existem mas so dois deram numero: limite nao muda",
			[]voto{{true, 80}, {true, 80}, {true, 0}},
			placar{N: 3, Exists: true, Kmh: 0, MandaExists: true, MandaKmh: false}},

		{"unanime em 3: manda nas duas perguntas",
			[]voto{{true, 60}, {true, 60}, {true, 60}},
			placar{N: 3, Exists: true, Kmh: 60, MandaExists: true, MandaKmh: true}},
	}

	for _, c := range casos {
		got := decidirVotos(c.vs)
		if got != c.quer {
			t.Errorf("%s:\n  got  %+v\n  quer %+v", c.nome, got, c.quer)
		}
	}
}

// A chave vem do app pra não divergir na 5ª casa; aqui só o formato é aceito.
func TestRidRe(t *testing.T) {
	ok := []string{"-23.29676_-45.96660", "0.00000_0.00000", "-8.12419_-35.31298"}
	for _, s := range ok {
		if !ridRe.MatchString(s) {
			t.Errorf("rid válido reprovou: %q", s)
		}
	}
	ruim := []string{
		"", "abc", "-23.2967_-45.96660", "-23.29676-45.96660",
		"-23.29676_", "-233.29676_-45.96660", "-23.296765_-45.96660",
		"../outro_doc", "-23.29676_-45.96660__x",
	}
	for _, s := range ruim {
		if ridRe.MatchString(s) {
			t.Errorf("rid inválido passou: %q", s)
		}
	}
}
