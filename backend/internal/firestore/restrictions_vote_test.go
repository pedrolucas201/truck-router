package firestore

import "testing"

const hex32 = "0123456789abcdef0123456789abcdef"
const hex32b = "fedcba9876543210fedcba9876543210"

// A confirmação de restrição tem o MESMO piso de 3 do radar
// (`isVerified => confirmedBy >= 3`) e tinha o mesmo furo: um doc de voto por
// uid, e o uid do Firebase troca a cada abertura em alguns aparelhos. Ponte
// baixa "verificada por 3 motoristas" que na verdade era um só é exatamente a
// marcação errada que o piso existe pra barrar.
func TestContarDonos(t *testing.T) {
	casos := []struct {
		nome                    string
		vs                      []VotoLido
		uid, install, action    string
		querConfirm, querReport int
	}{
		{"primeiro voto",
			nil, "u1", hex32, "confirm", 1, 0},

		// ⭐ O furo. Tres uids, um celular so: UM confirmador, nao tres.
		{"tres uids do MESMO aparelho contam um",
			[]VotoLido{
				{UID: "u1", Install: hex32, Action: "confirm"},
				{UID: "u2", Install: hex32, Action: "confirm"},
			},
			"u3", hex32, "confirm", 1, 0},

		// E tres motoristas de verdade seguem atingindo o piso: consertar nao
		// pode virar calar a curadoria.
		{"tres aparelhos distintos contam tres",
			[]VotoLido{
				{UID: "u1", Install: hex32, Action: "confirm"},
				{UID: "u2", Install: hex32b, Action: "confirm"},
			},
			"u3", "aaaaaaaabbbbbbbbccccccccdddddddd", "confirm", 3, 0},

		{"trocar de opiniao move o voto, nao soma",
			[]VotoLido{{UID: "u1", Install: hex32, Action: "confirm"}},
			"u1", hex32, "report", 0, 1},

		{"revotar o mesmo e idempotente",
			[]VotoLido{{UID: "u1", Install: hex32, Action: "confirm"}},
			"u1", hex32, "confirm", 1, 0},

		// Compatibilidade: o APK em campo nao manda install e segue contando
		// por uid, exatamente como antes.
		{"sem install cai no uid, como o app antigo",
			[]VotoLido{
				{UID: "u1", Action: "confirm"},
				{UID: "u2", Action: "confirm"},
			},
			"u3", "", "confirm", 3, 0},

		{"install invalido nao vira identidade",
			[]VotoLido{{UID: "u1", Install: "lixo", Action: "confirm"}},
			"u2", "lixo", "confirm", 2, 0},

		{"confirmacoes e reports convivem",
			[]VotoLido{
				{UID: "u1", Install: hex32, Action: "confirm"},
				{UID: "u2", Install: hex32b, Action: "report"},
			},
			"u3", "aaaaaaaabbbbbbbbccccccccdddddddd", "report", 1, 2},
	}

	for _, c := range casos {
		confirm, report := ContarDonos(c.vs, c.uid, c.install, c.action)
		if confirm != c.querConfirm || report != c.querReport {
			t.Errorf("%s:\n  got  confirm=%d report=%d\n  quer confirm=%d report=%d",
				c.nome, confirm, report, c.querConfirm, c.querReport)
		}
	}
}

func TestDonoRestricao(t *testing.T) {
	casos := []struct{ install, uid, quer string }{
		{hex32, "uid1", hex32},
		{"", "uid1", "uid1"},
		{"curto", "uid1", "uid1"},
		{"0123456789ABCDEF0123456789ABCDEF", "uid1", "uid1"},
	}
	for _, c := range casos {
		if got := Dono(c.install, c.uid); got != c.quer {
			t.Errorf("Dono(%q, %q) = %q, quer %q", c.install, c.uid, got, c.quer)
		}
	}
}
